/*
  Free Claude Code from its official pure-Python release wheel.

  Keep the main `version`, GitHub release `url`, and `hash` as plain strings;
  scripts/update.sh relies on them. The three small PyPI wheels below cover
  packages that are absent from nixpkgs or older than FCC's minimum version.

  FCC pins an exact CPython patch release and very fresh Python dependencies.
  Nix uses the compatible Python 3.14 series and relaxes those metadata bounds.
*/
{
  lib,
  fetchurl,
  python314Packages,
}:

let
  pname = "free-claude-code";
  version = "6.19.39";

  src = fetchurl {
    url = "https://github.com/Alishahryar1/free-claude-code/releases/download/v${version}/free_claude_code-${version}-py3-none-any.whl";
    hash = "sha256-V4y/XdzEzC/pGUcAFnd7m2TWeNwnLdoR5SJy3CjJzcM=";
  };

  python = python314Packages;

  discordPy = python.buildPythonPackage {
    pname = "discord-py";
    version = "2.7.1";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/f7/a7/17208c3b3f92319e7fad259f1c6d5a5baf8fd0654c54846ced329f83c3eb/discord_py-2.7.1-py3-none-any.whl";
      hash = "sha256-hJ3KLGOxcRRvOn8/iswEJICY6eYgNBLOPPJ0XyhPdDk=";
    };
    dependencies = with python; [
      aiohttp
      audioop-lts
    ];
    doCheck = false;
    pythonImportsCheck = [ "discord" ];
    meta.license = lib.licenses.mit;
  };

  githubCopilotSdk = python.buildPythonPackage {
    pname = "github-copilot-sdk";
    version = "1.0.34";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/6e/3f/9b8405bf4943dfb6ecd5d0ac2179e1fab896a61bd31273c94267faeae5c9/github_copilot_sdk-1.0.34-py3-none-any.whl";
      hash = "sha256-DZz/zNtZ9dkFEum5SnDUgoWaX8ng0tCSbhuxOKHlk8Q=";
    };
    dependencies = with python; [
      httpx
      pydantic
      python-dateutil
    ];
    doCheck = false;
    pythonImportsCheck = [ "copilot" ];
    meta.license = lib.licenses.mit;
  };

  nvidiaRivaClient = python.buildPythonPackage {
    pname = "nvidia-riva-client";
    version = "2.28.0";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/54/28/f1d08e8e8244c7735bfbaf16d572a37e24e06a7d64e45eefc36bd0b8ffce/nvidia_riva_client-2.28.0-py3-none-any.whl";
      hash = "sha256-V/ovTdcASnBYOsinlPprFlu+YqXShKUMLStF889OSYc=";
    };
    dependencies = with python; [
      grpcio
      grpcio-tools
      protobuf
      websockets
    ];
    pythonRelaxDeps = true;
    doCheck = false;
    pythonImportsCheck = [ "riva.client" ];
    meta.license = lib.licenses.mit;
  };
in
python.buildPythonApplication {
  inherit pname version src;
  format = "wheel";

  # Upstream's ==3.14.x pin tracks its uv-managed interpreter, not a language
  # feature requirement. Nixpkgs currently provides another Python 3.14 patch.
  pipInstallFlags = [ "--ignore-requires-python" ];
  pythonRelaxDeps = true;

  dependencies =
    (with python; [
      aiohttp
      anyio
      fastapi
      google-auth
      grpcio
      grpcio-tools
      httpx
      httpx2
      json5
      jsonschema
      loguru
      markdown-it-py
      openai
      packaging
      pydantic
      pyperclip
      pysocks
      python-dotenv
      python-telegram-bot
      requests
      ruamel-yaml
      simplejson
      socksio
      sqlalchemy
      tiktoken
      tomlkit
      uvicorn
    ])
    ++ [
      discordPy
      githubCopilotSdk
      nvidiaRivaClient
    ];

  postPatch = ''
    # A Python console script's sys.executable is not next to fcc-server in a
    # Nix store environment. Patch the still-zipped wheel to fall back to the
    # fcc-server on PATH; module launchers put the unmodified server there.
    python - <<'PY'
    import base64
    import hashlib
    import re
    from pathlib import Path
    from zipfile import ZipFile

    wheel = next(Path(".").glob("**/*.whl"))
    member = "free_claude_code/cli/launchers/common.py"
    old = (
        b"    if sibling.is_file() and os.access(sibling, os.X_OK):\n"
        b"        return [str(sibling), \"--auto-started\"]\n"
        b"    raise FileNotFoundError("
    )
    new = (
        b"    if sibling.is_file() and os.access(sibling, os.X_OK):\n"
        b"        return [str(sibling), \"--auto-started\"]\n"
        b"    command = shutil.which(f\"{name}{suffix}\")\n"
        b"    if command is not None:\n"
        b"        return [command, \"--auto-started\"]\n"
        b"    raise FileNotFoundError("
    )

    with ZipFile(wheel) as source:
        entries = [(info, source.read(info)) for info in source.infolist()]
    indices = [i for i, (info, _) in enumerate(entries) if info.filename == member]
    if len(indices) != 1:
        raise RuntimeError(f"Expected one {member} in FCC wheel")
    index = indices[0]
    info, data = entries[index]
    if data.count(old) != 1:
        raise RuntimeError("FCC server command patch did not match exactly once")
    patched = data.replace(old, new)
    digest = base64.urlsafe_b64encode(hashlib.sha256(patched).digest()).rstrip(b"=")
    entries[index] = (info, patched)

    with ZipFile(wheel.with_suffix(".tmp"), "w") as target:
        for info, data in entries:
            if info.filename.endswith(".dist-info/RECORD"):
                replacement = (
                    member.encode() + b",sha256=" + digest + b"," + str(len(patched)).encode()
                )
                pattern = rb"(?m)^" + re.escape(member.encode()) + rb",[^,\r\n]*,\d+"
                data, count = re.subn(pattern, replacement, data, count=1)
                if count != 1:
                    raise RuntimeError("Could not update FCC wheel RECORD")
            target.writestr(info, data)
    wheel.with_suffix(".tmp").replace(wheel)
    PY
  '';

  doCheck = false;
  pythonImportsCheck = [
    "free_claude_code.cli.entrypoints"
    "free_claude_code.runtime.bootstrap"
    "free_claude_code.providers.github_copilot.sdk"
    "free_claude_code.providers.nvidia_nim.voice"
  ];

  meta = {
    description = "Local proxy connecting coding agents to many AI providers";
    homepage = "https://github.com/Alishahryar1/free-claude-code";
    changelog = "https://github.com/Alishahryar1/free-claude-code/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "fcc-server";
  };
}
