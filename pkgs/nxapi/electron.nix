{ lib
, fetchFromGitHub
, buildNpmPackage
, nodejs_22
, electron_39
, python3
, pkg-config
, vips
, git
, makeBinaryWrapper
}:

let
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "samuelthomas2774";
    repo = "nxapi";
    rev = "v${version}";
    hash = "sha256-O2AN3eiZknwyI1SAInDck7ou79SpnWFWdFKoZeArVaY=";
    # rollup.config.js calls `git rev-parse HEAD` -> .git is required
    leaveDotGit = true;
  };

  # package-lock.json already present in the git repo
in
buildNpmPackage {
  pname = "nxapi-electron";
  inherit version src;

  nodejs = nodejs_22;

  # register-scheme is an optional git dependency (from discord-rpc)
  forceGitDeps = true;

  npmDepsHash = "sha256-5SORJHxpBLeje5XRPP36gesiary3qpnI8MdvTAsL8yM=";

  nativeBuildInputs = [ python3 pkg-config makeBinaryWrapper git ];

  # sharp (native module) must be compiled against nix's libvips
  buildInputs = [ vips ];

  # Build: tsc -> rollup (produces dist/bundle/ + dist/app/bundle/)
  dontNpmInstall = false;

  # No "build" script in package.json -> disable the npm build
  # and run tsc + rollup manually in postConfigure
  dontNpmBuild = true;

  # Electron npm package tries to download the electron binary from GitHub
  # -> blocked in the sandbox. We use nixpkgs' electron_39 at runtime.
  ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  # Compiles TS -> JS, then bundles via rollup
  # rollup.config.js calls `git rev-parse HEAD` (git in nativeBuildInputs)
  postConfigure = ''
    export NODE_ENV=production
    npx tsc
    npx rollup --config
  '';

  # Do NOT run electron-builder: we assemble the app manually
  # Uses nixpkgs' electron at runtime
  postInstall = ''
    mkdir -p $out/lib/nxapi-app
    cp -r dist $out/lib/nxapi-app/
    cp -r resources/app $out/lib/nxapi-app/resources-app

    # Removes node_modules and bin installed by npm (path conflict with
    # nxapi CLI because both packages expose lib/node_modules/nxapi/ and bin/nxapi).
    # The Electron app uses the precompiled bundle, so these directories are not needed.
    rm -rf $out/lib/node_modules $out/bin/nxapi

    # Wrapper launches nixpkgs' electron on the bundle
    makeBinaryWrapper ${electron_39}/bin/electron $out/bin/nxapi-app \
      --add-flags $out/lib/nxapi-app/dist/bundle/app-entry.cjs

    # .desktop + icon
    mkdir -p $out/share/applications
    cat > $out/share/applications/nxapi-app.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Nintendo Switch Online
    Comment=nxapi Electron app
    Exec=nxapi-app
    Icon=nxapi-app
    Categories=Utility;
    EOF
  '';

  meta = {
    description = "Nintendo Switch Online/Parental Controls app APIs - Electron app";
    homepage = "https://github.com/samuelthomas2774/nxapi";
    license = lib.licenses.agpl3Plus;
    mainProgram = "nxapi-app";
    platforms = lib.platforms.linux;
  };
}