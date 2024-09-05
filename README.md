# TizenFX Docs

Building TizenFX API Reference


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
