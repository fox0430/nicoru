# nicoru

A container runtime written in Nim.

NOTE: Work in progress.

# Features

- Create/Run a container

- Daemon-less

- Docker image support

- Management of container/image

- Seccomp

- Networking
  - host (default)
  - bridge
  - none

## Installation

nicoru can run on only GNU/Linux

### Requires

- Nim v1.6.0 or higher
- libseccomp
- ip(8) (Optional)
- iptables(8) (Optional)

```
nimble install nicoru
```

## Quick start

You need to be root to run nicoru.

```
sudo nicoru run ubuntu
```

Run the above command will download ubuntu:latest image from Docker Hub, run the container and attach it.

Please check [more](https://github.com/fox0430/nicoru/tree/develop/documents/command.md)

## License

MIT
