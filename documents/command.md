# nicoru commands

```
Usage:  nicoru [OPTIONS] COMMAND

Options:
  -v    Print version
  -h    Print help

Commands:
  create  Create a new container
  images  List images
  ps      List containers
  pull    Pull an image from a registry
  rm      Remove one containers
  rmi     Remove one images
  run     Run a command new container
  start   Start one stopped container
  stop    Stop one running containers
  log     Fetch the logs of a container
```

## Example

Run a container and attach it.

```
nicoru run ubuntu
```

Run a conatiner in the background.

```
nicoru run -d ubuntu
```

```
nicoru run -d alpine:latest
```

Pull an image from a registry (Docker Hub).

```
nicoru pull ubuntu
```

List containers.

```
nicoru ps
```

Remove a container.

```
nicoru rm $CONTAINER_ID
```

Stop a container.

```
nicoru stop $CONTAINER_ID
```

Start a container.

```
nicoru start $CONTAINER_ID
```

Show the logs of a container.

```
nicoru log $CONTAINER_ID
```

Remove an image.

```
nicoru rmi $IMAGE_ID
```
