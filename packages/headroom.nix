/*
  Headroom 0.40.0 with the MCP extra used by FCC's installer.

  The release wheel contains an abi3 native extension. MCP is kept on the
  compatible 1.x release instead of relaxing Headroom's <2 dependency.
*/
{
  lib,
  autoPatchelfHook,
  fetchurl,
  stdenv,
  python314Packages,
}:

let
  python = python314Packages;

  mcp = python.buildPythonPackage {
    pname = "mcp";
    version = "1.28.1";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/e2/5e/d118fce19f87a2e7d8101c35c8ae0ec289098a4df0ff244cec23e415aca0/mcp-1.28.1-py3-none-any.whl";
      sha256 = "2726bca5e7193f61c5dde8b12500a6de2d9acf6d1a1c0be9e8c2e706437991df";
    };
    dependencies = with python; [
      anyio
      cryptography
      httpx
      httpx-sse
      jsonschema
      pydantic
      pydantic-settings
      pyjwt
      python-multipart
      sse-starlette
      starlette
      typing-extensions
      typing-inspection
      uvicorn
    ];
    doCheck = false;
    pythonImportsCheck = [ "mcp" ];
    meta.license = lib.licenses.mit;
  };

  sources = {
    x86_64-linux = {
      url = "https://files.pythonhosted.org/packages/03/1c/383f4a2d33ad18d40869037ca6221e1db24bc4da5e92befe70793220b138/headroom_ai-0.40.0-cp310-abi3-manylinux_2_28_x86_64.whl";
      sha256 = "49b6d8a01c8eceb5b9e9a675720ed5e4cb24e467282642653aac7f2fd8faf47f";
    };
    aarch64-linux = {
      url = "https://files.pythonhosted.org/packages/c4/56/c5d5ad7e9ace7206f2400e6dce84b98e3387f9ccfb61a882edbb406299dc/headroom_ai-0.40.0-cp310-abi3-manylinux_2_28_aarch64.whl";
      sha256 = "140811066bfb7afe888f471be4a587375779af9de8dd76bb9a8126b52b8e930f";
    };
  };
in
python.buildPythonApplication {
  pname = "headroom-ai";
  version = "0.40.0";
  format = "wheel";
  src = fetchurl (
    sources.${stdenv.hostPlatform.system}
      or (throw "Headroom 0.40.0 has no wheel for ${stdenv.hostPlatform.system}")
  );

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dependencies = with python; [
    ast-grep-cli
    click
    httpx
    litellm
    mcp
    opentelemetry-api
    pydantic
    pyyaml
    rich
    starlette
    tiktoken
    tomlkit
    truststore
    uvicorn
  ];

  doCheck = false;
  pythonImportsCheck = [ "headroom" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/headroom --version
    $out/bin/headroom mcp install --help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Token optimization and context compression for coding agents";
    homepage = "https://docs.headroomlabs.ai";
    changelog = "https://github.com/headroomlabs-ai/headroom/blob/main/CHANGELOG.md";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "headroom";
  };
}
