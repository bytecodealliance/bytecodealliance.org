---
title: "Simplifying components for .NET/C# developers with componentize-dotnet"
author: "Eric Gregory"
date: "2024-09-03"
github_name: "ericgregory"
excerpt_separator: <!--end_excerpt-->
---
If you're a .NET/C# developer, `componentize-dotnet` makes it easy to compile your code to WebAssembly components using a single tool. This Bytecode Alliance project is a NuGet package that can be used to create a fully AOT-compiled component from a .NET application&mdash;giving .NET developers a component experience comparable to those in Rust and TinyGo.
<!--end_excerpt-->

`componentize-dotnet` serves as a one-stop shop for .NET developers, wrapping several tools into one:

 * [`NativeAOT-LLVM`](https://github.com/dotnet/runtimelab/tree/feature/NativeAOT-LLVM) (compilation)
 * [`wit-bindgen`](https://github.com/bytecodealliance/wit-bindgen) (WIT imports and exports)
 * [`wasm-tools`](https://github.com/bytecodealliance/wasm-tools) (component conversion)
 * [WASI SDK](https://github.com/WebAssembly/wasi-sdk) (SDK used by NativeAOT-LLVM)

In addition to everyone who worked on those projects, `componentize-dotnet` exists thanks to the work of [James Sturtevant](https://github.com/jsturtevant), [Steve Sanderson](https://github.com/SteveSandersonMS), [Scott Waye](https://github.com/yowl), [Joel Dice](https://github.com/dicej), [Timmy Silesmo](https://github.com/silesmo), and many other contributors. 

In this blog, we'll explore how .NET/C# developers can start building components today using .NET 9 Preview 7 and `componentize-dotnet`. 

## Getting started

For this walkthrough, we'll use the [.NET 9 SDK Preview 7](https://dotnet.microsoft.com/en-us/download/dotnet/9.0). You should also have the [`wasmtime` WebAssembly runtime](https://wasmtime.dev/) installed so you can run the Wasm binary that you produce. Optionally, you may wish to use the [C# Dev Kit extension](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csdevkit) for Visual Studio Code.

**Note:** While the .NET SDK is available on macOS and Linux and Wasm components can run on any OS, [the NativeAOT-LLVM compiler is limited to Windows at this time](https://github.com/dotnet/runtimelab/issues/1890#issuecomment-1221602595). Maintainers expect Linux and macOS support to arrive soon.  

Once you have the .NET SDK installed, create a new project:

```sh
dotnet new console -o hello
```
```sh
cd hello
```

The `componentize-dotnet` package depends on the `NativeAOT-LLVM` package, which resides at the `dotnet-experimental` package source, so you will need to make sure that NuGet is configured to refer to experimental packages. You can create a project-scoped NuGet configuration by running:

```sh
dotnet new nugetconfig
```

Edit your new `nuget.config` file to look like this:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
 <packageSources>
    <!--To inherit the global NuGet package sources remove the <clear/> line below -->
    <clear />
    <add key="dotnet-experimental" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-experimental/nuget/v3/index.json" />
    <add key="nuget" value="https://api.nuget.org/v3/index.json" />
 </packageSources>
</configuration>
```

Now back in the console we'll add the `BytecodeAlliance.Componentize.DotNet.Wasm.SDK` package:

```sh
dotnet add package BytecodeAlliance.Componentize.DotNet.Wasm.SDK --prerelease
```

In the `.csproj` project file, add the following to the `<PropertyGroup>`:

```xml
    <RuntimeIdentifier>wasi-wasm</RuntimeIdentifier>
    <UseAppHost>false</UseAppHost>
    <PublishTrimmed>true</PublishTrimmed>
    <InvariantGlobalization>true</InvariantGlobalization>
    <SelfContained>true</SelfContained>
    <MSBuildEnableWorkloadResolver>false</MSBuildEnableWorkloadResolver>
```

Now you're all set to build your console app, compiling to a `.wasm` component:

```sh
dotnet build
```

You can use [wasmtime](https://wasmtime.dev/) to run the component:

```sh
wasmtime bin\Debug\net9.0\wasi-wasm\native\hello.wasm
```
```text
Hello, World!
```

## Streamlining the component workflow

In real-world applications, you will frequently want to use WebAssembly Interface Type (WIT) definitions so your components can interoperate over a common interface. 

`componentize-dotnet` simplifies the process of fetching and using WIT interfaces, making it easy for your project file to reference a WIT artifact in an OCI registry. James Sturtevant created an excellent [demo](https://github.com/jsturtevant/wasi-http-oci/tree/master) that showcases this ability&mdash;we'll lightly adapt that demo here to use .NET 9. 

First replace the contents of `hello/Program.cs` with this:

```c#
using System.Text;
using ProxyWorld.wit.imports.wasi.http.v0_2_0;

namespace ProxyWorld.wit.exports.wasi.http.v0_2_0;

public class IncomingHandlerImpl: IIncomingHandler {
    public static void Handle(ITypes.IncomingRequest request, ITypes.ResponseOutparam responseOut) {
	var content = Encoding.ASCII.GetBytes("Hello, World!");
	var headers = new List<(string, byte[])> {
	    ("content-type", Encoding.ASCII.GetBytes("text/plain")),
	    ("content-length", Encoding.ASCII.GetBytes(content.Count().ToString()))
	};
	var response = new ITypes.OutgoingResponse(ITypes.Fields.FromList(headers));
	var body = response.Body();
	ITypes.ResponseOutparam.Set(responseOut, Result<ITypes.OutgoingResponse, ITypes.ErrorCode>.ok(response));
	using (var stream = body.Write()) {
	    stream.BlockingWriteAndFlush(content);
	}
	ITypes.OutgoingBody.Finish(body, null);
    }
}
```
If you're familiar with `wasi-http`, you'll recognize some of the types here, but your editor may give you error squigglies for the moment.

Now replace the contents of `hello.csproj` with the following:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <RuntimeIdentifier>wasi-wasm</RuntimeIdentifier>
    <UseAppHost>false</UseAppHost>
    <PublishTrimmed>true</PublishTrimmed>
    <InvariantGlobalization>true</InvariantGlobalization>
    <SelfContained>true</SelfContained>
    <MSBuildEnableWorkloadResolver>false</MSBuildEnableWorkloadResolver>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="BytecodeAlliance.Componentize.DotNet.Wasm.SDK" Version="0.2.0-preview00004" />
  </ItemGroup>

  <ItemGroup>
    <Wit Include="wit/wit.wasm" World="proxy" Registry="ghcr.io/webassembly/wasi/http:0.2.0" />
  </ItemGroup>
</Project>
```
The project file is mostly the same&mdash;the most significant change is that we've added a new `ItemGroup` for our WIT reference, which refers to an OCI registry.

If you're using the C# Dev Kit with Visual Studio Code, saving the project file will create WIT bindings for you to reference at `.\obj\Debug\net8.0\wasi-wasm\wit_bindgen\`, making it easier to use the `wasi-http` interface that you've just imported. (Your code should no longer show error squigglies, as well.) Regardless of your editor, now we can build a component that uses the interface:

```sh
dotnet build
```
```sh
wasmtime serve -S cli  .\bin\Debug\net9.0\wasi-wasm\native\hello.wasm --addr 127.0.0.1:3000
```
Check `localhost:3000` with your browser or `curl`:

```text
Hello, World!
```

## Looking ahead

As the .NET component ecosystem grows and evolves, `componentize-dotnet` will be an essential tool for building components with WIT files. Maintainers anticipate Linux and macOS support soon.

For more information on `componentize-dotnet`, including instructions on using WIT interfaces with .NET 9, composition, and exporting functionality, [see the `componentize-dotnet` readme](https://github.com/bytecodealliance/componentize-dotnet/blob/main/README.md). 

## Want to contribute?

Join the [Bytecode Alliance community on Zulip](https://bytecodealliance.zulipchat.com/), and explore the [meetings repository](https://github.com/bytecodealliance/meetings/tree/main) to find a SIG or community meeting that matches your interests. 

If you'd like to get involved with `componentize-dotnet`, check out the [issues](https://github.com/bytecodealliance/componentize-dotnet/issues) and join the conversation in the [C# channel of the Bytecode Alliance Zulip](https://bytecodealliance.zulipchat.com/#narrow/stream/407028-C.23.2F.2Enet-collaboration). 
