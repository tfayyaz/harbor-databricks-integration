#!/usr/bin/env bash
# Launch a throwaway EC2 worker, ship repo paths to it, run a command there with
# M2M credentials only (instance role -> Secrets Manager), copy jobs back, tear down.
#
# Usage (from the repo root): ec2_run.sh "<command>" <path>...
#   The paths are copied to /opt/run on the worker with their relative layout,
#   and the command runs in /opt/run. Results: everything under /opt/run/jobs.
# Env (defaults in brackets; a gitignored .env.local at the repo root is loaded first):
#   EC2_INSTANCE_PROFILE  required; role needs SSM core + GetSecretValue on the M2M secret
#   AWS_PROFILE, AWS_REGION [us-west-2], ITEM [2] (tag value)
#   INSTANCE_TYPE [m7i.xlarge]  VOLUME_GB [60] (keep <= 150)  HARBOR_VERSION [from pyproject.toml]
#   WORKER_ENV  extra "K=V ..." exported for the command (e.g. secret ids)
#   JOBS_DIR [jobs]  KEEP_INSTANCE [unset; 1 skips termination]  TIMEOUT_SEC [10800]
set -euo pipefail

cmd=${1:?usage: ec2_run.sh "<command>" <path>...}; shift
(( $# )) || { echo "ec2_run.sh: give at least one path to ship" >&2; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f $root/.env.local ]]; then set -a; . "$root/.env.local"; set +a; fi
profile=${EC2_INSTANCE_PROFILE:?EC2_INSTANCE_PROFILE required}
export AWS_REGION=${AWS_REGION:-us-west-2}
harbor_version=${HARBOR_VERSION:-$(sed -n 's/.*"harbor==\([^"]*\)".*/\1/p' "$root/pyproject.toml")}
timeout=${TIMEOUT_SEC:-10800}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="${JOBS_DIR:-jobs}/ec2-$stamp"
owner=$(aws sts get-caller-identity --query Arn --output text | sed 's#.*/##')
tag_list=(Project=harbor-databricks-integration "Item=${ITEM:-2}" "Owner=$owner" CreatedBy=ec2_run.sh)
ec2_tags=$(printf '{Key=%s,Value=%s},' $(printf '%s\n' "${tag_list[@]}" | sed 's/=/ /'))
bucket="harbor-dbx-item${ITEM:-2}-tmp-$(date +%s)-$RANDOM"
instance=""

cleanup() {
  set +e
  if [[ -n "$instance" && -z "${KEEP_INSTANCE:-}" ]]; then
    aws ec2 terminate-instances --instance-ids "$instance" >/dev/null && echo "terminated $instance"
  fi
  aws s3 rb "s3://$bucket" --force >/dev/null 2>&1 && echo "deleted s3://$bucket"
}
trap cleanup EXIT
trap 'exit 130' INT TERM   # route signals through the EXIT cleanup

# Files move through presigned URLs, so the worker role needs no S3 access.
# Sign against the regional endpoint: a new bucket answers the global one with 307.
aws s3 mb "s3://$bucket" >/dev/null
aws s3api put-bucket-tagging --bucket "$bucket" --tagging "TagSet=[${ec2_tags%,}]"
mac_flags=(); [[ $(uname) == Darwin ]] && mac_flags=(--no-mac-metadata)
COPYFILE_DISABLE=1 tar "${mac_flags[@]}" --exclude __pycache__ -czf - "$@" \
  | aws s3 cp - "s3://$bucket/bundle.tgz" --only-show-errors
presign() { # operation key
  uv run --quiet --no-project --with boto3 python -c '
import sys, boto3
from botocore.config import Config
op, key, bucket, region, ttl = sys.argv[1:]
s3 = boto3.client("s3", region_name=region, endpoint_url=f"https://s3.{region}.amazonaws.com",
                  config=Config(signature_version="s3v4"))
print(s3.generate_presigned_url(op, Params=dict(Bucket=bucket, Key=key), ExpiresIn=int(ttl) + 3600))
' "$1" "$2" "$bucket" "$AWS_REGION" "$timeout"
}
get_url=$(presign get_object bundle.tgz)
put_url=$(presign put_object jobs.tgz)

ami=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
instance=$(aws ec2 run-instances --image-id "$ami" --instance-type "${INSTANCE_TYPE:-m7i.xlarge}" \
  --iam-instance-profile "Name=$profile" \
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=${VOLUME_GB:-60},VolumeType=gp3,DeleteOnTermination=true}" \
  --metadata-options HttpTokens=required \
  --tag-specifications "ResourceType=instance,Tags=[${ec2_tags%,}]" "ResourceType=volume,Tags=[${ec2_tags%,}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "launched $instance (${INSTANCE_TYPE:-m7i.xlarge}, harbor $harbor_version); waiting for SSM"
for _ in $(seq 60); do
  [[ $(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance" \
        --query 'length(InstanceInformationList)' --output text) == 1 ]] && break
  sleep 10
done

remote=$(cat <<EOF
set -euo pipefail
export HOME=/root PATH=/root/.local/bin:/usr/local/bin:\$PATH AWS_REGION=$AWS_REGION
dnf install -y -q docker jq tar gzip >/dev/null
systemctl enable --now docker
# AL2023's docker has no compose plugin (Harbor needs it) and a buildx too old for compose builds.
plugins=/usr/local/lib/docker/cli-plugins; mkdir -p \$plugins
curl -fsSL -o \$plugins/docker-compose https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64
bx=\$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest | jq -r .tag_name)
curl -fsSL -o \$plugins/docker-buildx https://github.com/docker/buildx/releases/download/\$bx/buildx-\$bx.linux-amd64
chmod +x \$plugins/*
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh >/dev/null
uv tool install --quiet --python 3.12 harbor==$harbor_version
mkdir -p /opt/run && curl -fsS '$get_url' | tar xz -C /opt/run
cd /opt/run
export HARBOR=harbor JOBS_DIR=/opt/run/jobs ${WORKER_ENV:-}
set +e; ( $cmd ) > /opt/run/command.log 2>&1; rc=\$?; set -e
tail -60 /opt/run/command.log
for r in /opt/run/jobs/*/*/result.json; do
  [[ -f \$r ]] && jq -c '{task: .task_name, agent: .agent_info.name, version: .agent_info.version,
    model: .agent_info.model_info.name, reward: .verifier_result.rewards.reward,
    exception: .exception_info.exception_type}' "\$r"
done
mkdir -p /opt/run/jobs && cp /opt/run/command.log /opt/run/jobs/
tar czf /tmp/jobs.tgz -C /opt/run jobs
code=\$(curl -sS -o /dev/null -w '%{http_code}' -X PUT --upload-file /tmp/jobs.tgz '$put_url')
echo "command exit=\$rc results upload http=\$code"; [[ \$code == 200 && \$rc == 0 ]]
EOF
)
cmd_id=$(aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
  --timeout-seconds 600 --parameters "$(jq -n --arg c "$remote" --arg t "$timeout" '{commands:[$c],executionTimeout:[$t]}')" \
  --query Command.CommandId --output text)
echo "running on $instance (ssm command $cmd_id)"
while :; do
  status=$(aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance" \
    --query Status --output text 2>/dev/null || echo Pending)
  case $status in Pending|InProgress|Delayed) sleep 30 ;; *) break ;; esac
done
aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance" \
  --query StandardOutputContent --output text | tail -40
echo "ssm status: $status"

mkdir -p "$out"
aws s3 cp "s3://$bucket/jobs.tgz" - --only-show-errors | tar xz -C "$out" && echo "results in $out"
[[ $status == Success ]]
