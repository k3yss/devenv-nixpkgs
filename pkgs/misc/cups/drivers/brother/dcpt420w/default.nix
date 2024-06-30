{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, perl
, gnused
, ghostscript
, file
, coreutils
, gnugrep
, which
}:

let
  arches = [ "x86_64" "i686" ];

  runtimeDeps = [
    ghostscript
    file
    gnused
    gnugrep
    coreutils
    which
  ];
in

stdenv.mkDerivation rec {
  pname = "cups-brother-dcpt420w";
  version = "3.5.0-1";

  nativeBuildInputs = [ dpkg makeWrapper autoPatchelfHook ];
  buildInputs = [ perl ];

  src = fetchurl {
    #https://download.brother.com/welcome/dlf105168/dcpt420wpdrv-3.5.0-1.i386.deb
    url = "https://download.brother.com/welcome/dlf105168/dcpt420wpdrv-${version}.i386.deb";
    hash = "sha256-Pt6BmmWuw3nsdnb3rAysq9cIefuq8seXjurkBsDhwfI=";
  };

  unpackPhase = "dpkg-deb -x $src .";

  patches = [
    # The brother lpdwrapper uses a temporary file to convey the printer settings.
    # The original settings file will be copied with "400" permissions and the "brprintconflsr3"
    # binary cannot alter the temporary file later on. This fixes the permissions so the can be modified.
    # Since this is all in briefly in the temporary directory of systemd-cups and not accessible by others,
    # it shouldn't be a security concern.
    ./fix-perm.patch
  ];

  installPhase = ''

    #run the preInstall hook for handling nix bs
    runHook preInstall

    # create the nix store path
    mkdir -p $out

    # copy dpkg files to opt directory
    cp -ar opt $out/opt


    # delete unnecessary files for the current architecture
  '' + lib.concatMapStrings
    (arch: ''
      echo Deleting files for ${arch}
      rm -r "$out/opt/brother/Printers/dcpt420w/lpd/${arch}"
    '')
    (builtins.filter (arch: arch != stdenv.hostPlatform.linuxArch) arches) + ''



    # bundled scripts don't understand the arch subdirectories for some reason
    ln -s \
      "$out/opt/brother/Printers/dcpt420w/lpd/${stdenv.hostPlatform.linuxArch}/"* \
      "$out/opt/brother/Printers/dcpt420w/lpd/"



    # Fix global references and replace auto discovery mechanism with hardcoded values
    substituteInPlace $out/opt/brother/Printers/dcpt420w/lpd/filter_dcpt420w \
      --replace "my \$BR_PRT_PATH =" "my \$BR_PRT_PATH = \"$out/opt/brother/Printers/dcpt420w\"; #" \
      --replace "PRINTER =~" "PRINTER = \"dcpt420w\"; #"
    substituteInPlace $out/opt/brother/Printers/dcpt420w/cupswrapper/brother_lpdwrapper_dcpt420w \
      --replace "my \$basedir = C" "my \$basedir = \"$out/opt/brother/Printers/dcpt420w\" ; #" \
      --replace "PRINTER =~" "PRINTER = \"dcpt420w\"; #"




    # Make sure all executables have the necessary runtime dependencies available
    find "$out" -executable -and -type f | while read file; do
      wrapProgram "$file" --prefix PATH : "${lib.makeBinPath runtimeDeps}"
    done

    # Symlink filter and ppd into a location where CUPS will discover it
    mkdir -p $out/lib/cups/filter
    mkdir -p $out/share/cups/model
    mkdir -p $out/etc/opt/brother/Printers/dcpt420w/inf

    ln -s $out/opt/brother/Printers/dcpt420w/inf/brdcpt420wrc \
          $out/etc/opt/brother/Printers/dcpt420w/inf/brdcpt420wrc

    ln -s \
      $out/opt/brother/Printers/dcpt420w/cupswrapper/brother_lpdwrapper_dcpt420w \
      $out/lib/cups/filter/brother_lpdwrapper_dcpt420w

    ln -s \
      $out/opt/brother/Printers/dcpt420w/cupswrapper/brother-dcpt420w-cups-en.ppd \
      $out/share/cups/model/

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "http://www.brother.com/";
    description = "Brother DCPT420W printer driver";
    license = licenses.unfree;
    platforms = builtins.map (arch: "${arch}-linux") arches;
    maintainers = [ maintainers.k3yss ];
  };
}
