# Building your first Pode app

!!! note
    Before starting, ensure you've [installed](../Installation) Pode.

The following steps will run you through creating your first Pode app, and give you an overview to some of the basic features.

## Setup

* First, create a `/my-first-pode-app` directory, this should be where ever you put your project/learning code.

* Open PowerShell, and navigate to the above directory.

* Run `pode init` in the console, this will create a basic `package.json` file for you - see the [`CLI`](../CLI) reference for more information.

    * The `init` action will ask for some input, leave everything as default (just press enter).

```powershell
λ  pode init
name (my-first-pode-app):
version (1.0.0):
description:
entry point (./server.ps1):
author:
license (MIT):
Success, saved package.json
```

* In your favourite text editor, create a `server.ps1` file within the directory.

## REST Server

* Within your `server.ps1` file, first you need to create the [`server`](../../Functions/Core/Server). This is where the main script will go that defines how the server should function:

```powershell
server {
    # logic
}
```

* Now we have our server, we need to get it to [`listen`](../../Functions/Core/Listen) on an endpoint. This will allow us to receive requests and respond to them. The below tells your server to listen on `localhost` and port `8080` for HTTP requests:

```powershell
server {
    listen localhost:8080 http
}
```

* Our simple server will have a single GET [`route`](../../Tutorials/Routes/Overview); it will be invoked when the root (`/`) of the server is called (ie: `http://localhost:8080/`). This route will respond with a simple JSON response:

```powershell
server {
    listen localhost:8080 http

    route get '/' {
        json @{ 'value' = 'Hello, world!' }
    }
}
```

* Save the file, and run `pode start` (or `./server.ps1`) from the console. This will start the server listening on `localhost:8080`. When `http://localhost:8080/` is hit, the server will respond with:

```json
{
    "value": "Hello, world!"
}
```

## More Tutorials

* To see how to create web pages using Pode, [see here](../../Tutorials/Routes/WebPages)
* To see how to do basic login/logout pages, [see here](../../Tutorials/Routes/LoginPage)
* For more tutorials, [see here](../../Tutorials/Basics)