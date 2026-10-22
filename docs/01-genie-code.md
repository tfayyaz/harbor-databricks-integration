# 1. Genie Code CLI with Unity AI Gateway

Status: not started.

## Setup

## Run locally

Local runs use [Colima](https://github.com/abiosoft/colima) as the Docker runtime on macOS. Colima is free and open source, runs from the command line with no desktop app or licence, and lets you set the VM's CPU, memory and disk explicitly (`colima start --cpu 8 --memory 16 --disk 100`), which matters because Harbor starts one container per trial. On Apple Silicon it runs arm64 images natively. Docker Desktop also works; Harbor only needs a working `docker` and `docker compose`.

If `docker run` fails with `input/output error` under `/var/lib/containerd`, the Colima VM's disk is damaged. `colima restart` fixes it, but it stops every running container, so check `docker ps` first on a shared machine.

## Run on EC2

## Results

| Agent | Model | Local | EC2 | Notes |
|---|---|---|---|---|
