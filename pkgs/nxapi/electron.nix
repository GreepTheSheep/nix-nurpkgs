{ lib
, fetchFromGitHub
, fetchurl
, buildNpmPackage
, nodejs_22
, electron_42
, python3
, pkg-config
, vips
, git
, makeBinaryWrapper
, makeDesktopItem
, copyDesktopItems
, imagemagick
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

  # Official project logo (GitLab project avatar)
  icon = fetchurl {
    url = "https://gitlab.fancy.org.uk/uploads/-/system/project/avatar/96/af3fa9d9821d461ab832bcf4b0d1eece.png";
    hash = "sha256-S1RtcQwrzB+jBFJIEu7+ogrAbCPmSp8dC3z/vaHmurI=";
  };

  # Electron derives the X11 WM_CLASS from the application directory's
  # package.json when launched with a directory (instead of a script file):
  #   productName "Nintendo Switch Online" -> "nintendo-switch-online"
  # The desktop entry's StartupWMClass must match this value.
  appDir = "lib/nxapi-app";

  desktopItem = makeDesktopItem {
    name = "nxapi-app";
    desktopName = "Nintendo Switch Online";
    genericName = "Nintendo Switch app APIs";
    comment = "Nintendo Switch Online/Parental Controls app APIs";
    exec = "nxapi-app %U";
    icon = "nxapi-app";
    terminal = false;
    categories = [ "Utility" ];
    # Registered protocol handlers (see nxapi src/app/main/index.ts)
    mimeTypes = [
      "x-scheme-handler/com.nintendo.znca"
      "x-scheme-handler/npf71b963c1b7b6d119"
      "x-scheme-handler/npf54789befb391a838"
    ];
    startupWMClass = "nintendo-switch-online";
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

  nativeBuildInputs = [ python3 pkg-config makeBinaryWrapper git copyDesktopItems imagemagick ];

  desktopItems = [ desktopItem ];

  # sharp (native module) must be compiled against nix's libvips
  buildInputs = [ vips ];

  # Build: tsc -> rollup (produces dist/bundle/ + dist/app/bundle/)
  dontNpmInstall = false;

  # No "build" script in package.json -> disable the npm build
  # and run tsc + rollup manually in postConfigure
  dontNpmBuild = true;

  # The electron npm package (v21, pulled by nxapi's devDependencies) tries to
  # download the electron binary from GitHub in its postinstall -> blocked in
  # the sandbox. We use nixpkgs' electron_42 at runtime instead.
  ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  # Compiles TS -> JS, then bundles via rollup
  # rollup.config.js calls `git rev-parse HEAD` (git in nativeBuildInputs)
  postConfigure = ''
    export NODE_ENV=production
    npx tsc
    npx rollup --config
  '';

  # Do NOT run electron-builder: we assemble the app manually.
  # The app is laid out as an Electron "app directory" so that Electron derives
  # the correct X11 WM_CLASS (from package.json's productName) when it is passed
  # a directory instead of a script path. This is also what the bundle expects
  # for its resources: <appdir>/resources/{app,common} and <appdir>/dist/app/bundle.
  postInstall = ''
    appdir=$out/${appDir}
    mkdir -p $appdir
    cp -r dist $appdir/
    mkdir -p $appdir/resources
    cp -r resources/app $appdir/resources/app
    cp -r resources/common $appdir/resources/common

    # Minimal package.json making $appdir a valid Electron application.
    cat > $appdir/package.json <<EOF
    {
      "name": "nxapi-app",
      "productName": "Nintendo Switch Online",
      "version": "${version}",
      "type": "module",
      "main": "dist/bundle/app-entry.cjs"
    }
    EOF

    # Removes node_modules and bin installed by npm (path conflict with
    # nxapi CLI because both packages expose lib/node_modules/nxapi/ and bin/nxapi).
    # The Electron app uses the precompiled bundle, so these directories are not needed.
    rm -rf $out/lib/node_modules $out/bin/nxapi

    # Wrapper launches nixpkgs' electron on the app directory
    makeBinaryWrapper ${electron_42}/bin/electron $out/bin/nxapi-app \
      --add-flags $appdir

    # Multi-size launcher icon (hicolor theme)
    for size in 16 32 48 64 128 256; do
      mkdir -p "$out/share/icons/hicolor/''${size}x''${size}/apps"
      magick ${icon} -resize "''${size}x''${size}" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/nxapi-app.png"
    done
  '';

  meta = {
    description = "Nintendo Switch Online/Parental Controls app APIs - Electron app";
    homepage = "https://github.com/samuelthomas2774/nxapi";
    license = lib.licenses.agpl3Plus;
    mainProgram = "nxapi-app";
    platforms = lib.platforms.linux;
  };
}