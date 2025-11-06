# TizenFX Docs

Building TizenFX API Reference

The main purpose of those scripts is to build the whole documentation, multiple versions of TizenFX
to be uploaded to reference site.

Use `build-local.sh` script if you need to build the documentation for the current state of the TizenFX repository.

## Prerequisites
- .NET SDK = 6.0.x : https://dotnet.microsoft.com/download/dotnet/6.0
- DocFX = 2.61.0 : https://github.com/dotnet/docfx

## Build documents
```sh
$ ./build.sh
```

## Build documents with the specific docfx file
```sh
# Build documents for internals API
$ DOCFX_FILE=docfx_internals.json ./build.sh

# Build documents for docs.tizen.org
$ DOCFX_FILE=docfx_tizen_docs.json ./build.sh

```

## Serve local built documents
```
$ docfx serve _site
```
