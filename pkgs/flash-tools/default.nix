{ stdenv, lib, makeWrapper, bzip2_1_1, fetchurl, python3, perl, xxd,
  libxml2, coreutils, gnugrep, gnused, gnutar, gawk, which, gzip, cpio,
  bintools-unwrapped, findutils, util-linux, dosfstools, lz4, gcc, dtc, qemu,
  runtimeShell, fetchzip, bc, openssl_1_1,

  bspSrc, l4tVersion,
}:

let
  JAOi_lowtemp_overlay = fetchzip {
    url = "https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v4.1/overlay_jaoi_low_temp_35.4.1.tar.gz";
    sha256 = "sha256-60qziBK2lw8asr6hjcWY4i/dYmdjF9g9PSDka6E/zzc=";
    stripRoot = false;
  };

  flash-tools = stdenv.mkDerivation {
    pname = "flash-tools";
    version = l4tVersion;

    src = bspSrc;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [
      (python3.withPackages (p: with p; [ pyyaml ]))
      perl
    ];

    patches = [ ./flash-tools.patch ];

    postPatch = ''
      # Needed in Jetpack 5
      substituteInPlace flash.sh \
        --replace /usr/bin/xmllint ${libxml2}/bin/xmllint

      # Remove stuff not needed for flashing
      find . -iname '*.deb' -delete
      find . -iname '*.tbz2' -delete

      # We should never be flashing upstream's kernel, so just remove it so we get errors if it is used
      #rm -f kernel/Image*

      # Remove the big nv_tegra dir, since its not needed by flash scripts.
      # However, save the needed bsp_version file
      mv nv_tegra/bsp_version .
      rm -rf nv_tegra
      mkdir nv_tegra
      mv bsp_version nv_tegra

      cp -r ${JAOi_lowtemp_overlay}/Linux_for_Tegra/bootloader/. bootloader
      chmod u+w -R .
    '' + (lib.optionalString (!stdenv.hostPlatform.isx86) ''
      # Wrap x86 binaries in qemu
      pushd bootloader/ >/dev/null
      for filename in chkbdinfo mkbctpart mkbootimg mksparse tegrabct_v2 tegradevflash_v2 tegrahost_v2 tegrakeyhash tegraopenssl tegraparser_v2 tegrarcm_v2 tegrasign_v2; do
        mv "$filename" ."$filename"-wrapped
        cat >"$filename" <<EOF
      #!${runtimeShell}
      exec -a "\$0" ${qemu}/bin/qemu-i386 "$out/bootloader/.$filename-wrapped" "\$@"
      EOF
        chmod +x "$filename"
      done
      popd >/dev/null
    '');

    # Create update payloads with:
    # ./l4t_generate_soc_bup.sh t19x

    dontConfigure = true;
    dontBuild = true;
    noDumpEnvVars = true;

    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';

    # Stuff to put into PATH for flash.sh
    # wrapProgram doesn't work here because it refers to the wrapped program by
    # absolute path, and flash-script copies the entire flash-tools dir before
    # running
    passthru.flashDeps = [
      coreutils gnugrep gnused gnutar gawk xxd which gzip cpio bintools-unwrapped
      findutils python3 util-linux dosfstools lz4 bc openssl_1_1

      # Needed by bootloader/tegraflash_impl_t234.py
      gcc dtc
    ];
  };

in flash-tools
