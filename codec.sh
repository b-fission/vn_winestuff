#!/bin/bash

echo
echo "Helper script to install codecs for VNs on wine (v2025-06-29)"
echo

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

Quit() { echo; exit; }
Heading() { echo; echo "[INSTALL] $@"; }

CheckEnv()
{
    # check for wine. it can be defined in $WINE or found in $PATH
    if [ "$WINE" = "" ]; then WINE="wine"; fi

    if ! command -v "$WINE" >/dev/null; then
        echo "There is no usable wine executable in your PATH."
        echo "Either set it or the WINE variable and try again."
        Quit
    fi

    # check if WINEPREFIX is defined
    if [ "$WINEPREFIX" = "" ]; then
        WINEPREFIX="~/.wine"
        echo "WINEPREFIX is not set. Going to use $WINEPREFIX"
    else
        echo "WINEPREFIX is $WINEPREFIX"
    fi

    # determine arch if it's not defined yet
    if [ "$WINEARCH" = "" ]; then
        if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
            echo "A wine prefix does not appear to exist yet."
            echo "Please run  wineboot -i  to initialize it."
            Quit
        elif [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
            ARCH="win64"
        else
            ARCH="win32"
        fi
        echo "WINEARCH seems to be $ARCH"
    else
        ARCH=$WINEARCH
        echo "WINEARCH specified as $ARCH"
    fi

    # check for valid WINEARCH  (also end current wine session)
    WINEDEBUG="-all" WINEARCH=$ARCH "$WINE" wineboot -e || Quit
}

RUN()
{
    echo "[run] $WINE $@"
    WINEDEBUG="-all" "$WINE" $@

    if [ $? -ne 0 ]; then echo "some kind of error occurred."; Quit; fi
}

RUN64()
{
    if command -v "${WINE}64" >/dev/null; then
        WINECMD="${WINE}64"
    else
        WINECMD="$WINE"
    fi
    echo "[run64] ${WINECMD} $@"
    WINEDEBUG="-all" "${WINECMD}" $@

    if [ $? -ne 0 ]; then echo "some kind of error occurred."; Quit; fi
}

GetWindowsVer()
{
    #OSVER=$(WINEDEBUG="-all" "$WINE" winecfg -v | tr -d '\r')
    OSVER=$(WINEDEBUG="-all" "$WINE" winecfg -v 2>&1 | grep win | tr -d '\r')
    #echo "OS Ver is $OSVER"
}

SetWindowsVer()
{
    REQVER=$1

    # WinXP 64-bit has its own identifier
    if [[ $REQVER = "winxp" && $ARCH = "win64" ]]; then REQVER="winxp64"; fi

    RUN winecfg -v $REQVER
    GetWindowsVer
}

GetSysDir()
{
    if [ $ARCH = "win64" ]; then SYSDIR="syswow64"; else SYSDIR="system32"; fi
}

OverrideDll()
{
    if [ "$2" != "" ]; then DATA="/d $2"; else DATA=""; fi
    RUN reg add "HKCU\\Software\\Wine\\DllOverrides" /f /t REG_SZ /v $1 $DATA
}

SetClassDll32()
{
    if [ $ARCH = "win64" ]; then WOWNODE="\\Wow6432Node"; else WOWNODE=""; fi
    REGKEY="HKLM\\Software${WOWNODE}\\Classes\\CLSID\\{$1}\\InprocServer32"
    RUN reg add $REGKEY /f /t REG_SZ /ve /d $2
}

Hash_SHA256()
{
    if command -v sha256sum >/dev/null; then
        HASH=$(sha256sum "$1" | sed -e "s/ .*//" | tr -d '\n')
    elif command -v openssl >/dev/null; then
        HASH=$(openssl sha256 "$1" | sed -e 's/SHA.* //')
    else
        echo "no usable sha256 utility available, cannot continue."; Quit
    fi

    if [ $HASH != $2 ]; then
        echo "... hash mismatch on $1"
        echo "download hash $HASH"
        echo "expected hash $2"
        Quit
    fi
}

DownloadFile()
{ # args: $1=output_subdir $2=output_name $3=url $4=hash
    DLFILE=$SCRIPT_DIR/$1/$2
    DLFILEWIP=${DLFILE}.download

    # download file if we don't have it yet
    if [ ! -f "$DLFILE" ]; then
        # download
        mkdir -p "$SCRIPT_DIR/$1"

        if command -v wget >/dev/null; then
            wget --progress=bar -O "$DLFILEWIP" $3
        elif command -v curl >/dev/null; then
            curl -L -o "$DLFILEWIP" $3
        else
            echo "no downloader utility available, cannot continue."; Quit
        fi

        # delete download on failure
        RET=$?
        FSIZE=$(wc -c "$DLFILEWIP" | sed -e 's/ .*//')
        if [[ $RET -ne 0 || $FSIZE -eq 0 ]]; then
            echo "error occurred while downloading $2"
            rm $DLFILEWIP 2> /dev/null
            Quit
        fi

        mv "$DLFILEWIP" "$DLFILE"
    fi

    # file hash must match, otherwise quit
    if [ -f "$DLFILE" ]; then
        [ "$4" != "nohash" ] && Hash_SHA256 "$DLFILE" $4
    else
        echo "$1 is not found, cannot continue."; Quit
    fi
}

DownloadFileInternal()
{
    BASEURL="https://raw.githubusercontent.com/b-fission/vn_winestuff/master"
    DownloadFile $1 $2 $BASEURL/$1/$2 $3
}


# ============================================================================

Disable_winegstreamer()
{
    OverrideDll winegstreamer ""
    OverrideDll ir50_32 ""
    OverrideDll wmvcore ""
}

Copy_WineVkd3dFiles()
{
    WINE_BASEPATH=$(cd -- "$(dirname "`command -v "$WINE"`")/.." &> /dev/null && pwd)

    if [ -f "$WINE_BASEPATH/lib/vkd3d/libvkd3d-1.dll" ]; then
        if [ ! -f "$WINEPREFIX/drive_c/windows/$SYSDIR/libvkd3d-1.dll" ]; then
            echo "going to copy libvkd3d dlls into prefix"

            # copy 32-bit files
            cp -v "$WINE_BASEPATH/lib/vkd3d"/*.dll "$WINEPREFIX/drive_c/windows/$SYSDIR"

            # copy 64-bit files
            if [ $ARCH = "win64" ]; then
                cp -v "$WINE_BASEPATH/lib64/vkd3d"/*.dll "$WINEPREFIX/drive_c/windows/system32"
            fi
        fi
    fi
}

# ============================================================================

Install_mf()
{
    Heading "mf"

    WORKDIR=$SCRIPT_DIR/mf
    if ! command -v unzip >/dev/null; then echo "unzip is not available, cannot continue."; Quit; fi

    OVERRIDE_DLL="colorcnv dxva2 evr mf mferror mfplat mfplay mfreadwrite msmpeg2adec msmpeg2vdec sqmapi wmadmod wmvdecod"
    REGISTER_DLL="colorcnv evr msmpeg2adec msmpeg2vdec wmadmod wmvdecod"

    # install 32-bit components
    DownloadFileInternal mf mf32.zip 2600aeae0f0a6aa2d4c08f847a148aed7a09218f1bfdc237b90b43990644cbbd

    unzip -o -q -d "$WORKDIR/temp" "$WORKDIR/mf32.zip" || Quit;
    cp -vf "$WORKDIR/temp/syswow64"/* "$WINEPREFIX/drive_c/windows/$SYSDIR"

    Disable_winegstreamer
    for DLL in $OVERRIDE_DLL; do OverrideDll $DLL native; done

    RUN "c:/windows/$SYSDIR/reg.exe" import "$WORKDIR/temp/mf.reg"
    RUN "c:/windows/$SYSDIR/reg.exe" import "$WORKDIR/temp/wmf.reg"

    for DLL in $REGISTER_DLL; do RUN c:/windows/$SYSDIR/regsvr32.exe /s "c:/windows/$SYSDIR/$DLL.dll"; done

    # install 64-bit components
    if [ $ARCH = "win64" ]; then
        DownloadFileInternal mf mf64.zip 8a316d8c2c32a7e56ed540026e79db76879cc61794b3331301390013339e8ad7

        unzip -o -q -d "$WORKDIR/temp" "$WORKDIR/mf64.zip" || Quit;
        cp -vf "$WORKDIR/temp/system32"/* "$WINEPREFIX/drive_c/windows/system32"

        RUN64 "c:/windows/system32/reg.exe" import "$WORKDIR/temp/mf.reg"
        RUN64 "c:/windows/system32/reg.exe" import "$WORKDIR/temp/wmf.reg"

        for DLL in $REGISTER_DLL; do RUN64 c:/windows/system32/regsvr32.exe /s "c:/windows/system32/$DLL.dll"; done
    fi

    # cleanup
    rm -fr "$WORKDIR/temp"
}

Install_quartz_dx()
{
    Heading "quartz_dx"

    DownloadFileInternal quartz_dx amstream.dll 0e87db588c7740c7c8e9d19af9b4843e497759300888445388ff915c5ccd145c
    DownloadFileInternal quartz_dx devenum.dll ab49f2ebb9f99b640c14a4a1d830b35685aa758c7b1f5c62d77fdb6e09081387
    DownloadFileInternal quartz_dx quartz.dll a378764866d8dd280e63dda4e62c5b10626cf46a230768fb24c3c3d5f7263b87

    cp -fv "$SCRIPT_DIR/quartz_dx/"{quartz,devenum,amstream}.dll "$WINEPREFIX/drive_c/windows/$SYSDIR"

    Disable_winegstreamer
    OverrideDll amstream native,builtin
    OverrideDll devenum native,builtin
    OverrideDll quartz native,builtin

    RUN c:/windows/$SYSDIR/regsvr32.exe /s c:/windows/$SYSDIR/amstream.dll
    RUN c:/windows/$SYSDIR/regsvr32.exe /s c:/windows/$SYSDIR/devenum.dll
    RUN c:/windows/$SYSDIR/regsvr32.exe /s c:/windows/$SYSDIR/quartz.dll

    # also install dgVoodoo2 for compatibility
    DownloadFileInternal dgvoodoo2 dgVoodoo2_8_1.zip 15f95a5c163f74105a03479fb2e868c04c432680e0892bf559198a93a7cd1c25

    unzip -o -q -d "$SCRIPT_DIR/dgvoodoo2/temp" "$SCRIPT_DIR/dgvoodoo2/dgVoodoo2_8_1.zip" "MS/x86/DDraw.dll"
    cp -fv "$SCRIPT_DIR/dgvoodoo2/temp/MS/x86/DDraw.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/ddraw.dll"
    cp -fv "$SCRIPT_DIR/dgvoodoo2/dgVoodoo.conf" "$WINEPREFIX/drive_c/windows/$SYSDIR"

    OverrideDll ddraw native

    # cleanup
    rm -fr "$SCRIPT_DIR/dgvoodoo2/temp"
}

Install_quartz2()
{
    Heading "quartz2"

    DownloadFileInternal quartz2 amstream.dll 26012b03ad7c0802a2f26bf89c6510a78f6f4ae44d5e5eed164e22db7db334f0
    DownloadFileInternal quartz2 devenum.dll ed55a2ab8ab2675f277bedae94d30e0fb4e0174e92014c0b95d51e9a6379c301
    DownloadFileInternal quartz2 quartz2.dll fa52a0d0647413deeef57c5cb632f73a97a48588c16877fc1cc66404c3c21a2b

    Disable_winegstreamer
    OverrideDll amstream native,builtin
    OverrideDll devenum native,builtin
    OverrideDll quartz native,builtin

    cp -fv "$SCRIPT_DIR/quartz2/"{quartz2,amstream,devenum}.dll "$WINEPREFIX/drive_c/windows/$SYSDIR"
    #RUN c:/windows/$SYSDIR/regsvr32.exe /s amstream.dll
    RUN c:/windows/$SYSDIR/regsvr32.exe /s devenum.dll
    RUN c:/windows/$SYSDIR/regsvr32.exe /s quartz2.dll

    # use wine's quartz for these DirectShow filters
    DLL="c:\\windows\\$SYSDIR\\quartz.dll"
    SetClassDll32 "79376820-07D0-11CF-A24D-0020AFD79767" $DLL #DirectSound
    SetClassDll32 "6BC1CFFA-8FC1-4261-AC22-CFB4CC38DB50" $DLL #DefaultVideoRenderer
    SetClassDll32 "70E102B0-5556-11CE-97C0-00AA0055595A" $DLL #VideoRenderer
    SetClassDll32 "51B4ABF3-748F-4E3B-A276-C828330E926A" $DLL #VMR9
    SetClassDll32 "B87BEB7B-8D29-423F-AE4D-6582C10175AC" $DLL #VMR7
}

Install_mciqtz32()
{
    Heading "mciqtz32"

    DownloadFileInternal mciqtz32 mciqtz32.dll 43d131bfd6884e2d8d0317aabaf0564e36937347ab43feccfc2b1c9d38c8527b
    cp -fv "$SCRIPT_DIR/mciqtz32/mciqtz32.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/mciqtz32.dll"

    Disable_winegstreamer
    OverrideDll mciqtz32 native
}

Install_wmp11()
{
    Heading "wmp11"

    PREV_OSVER=$OSVER
    case $ARCH in
        win32) wmf="wmfdist11.exe";    validhash=ddfea7b588200d8bb021dbf1716efb9f63029a0dd016d4c12db89734852e528d;;
        win64) wmf="wmfdist11-64.exe"; validhash=eba63fa648016f3801e503fc91d9572b82aeb0409e73c27de0b4fbc51e81e505;;
        *) Quit;;
    esac

    DownloadFileInternal wmp11 $wmf $validhash

    SetWindowsVer winxp
    Disable_winegstreamer
    OverrideDll qasf native
    OverrideDll wmvcore native
    OverrideDll wmvdecod native
    OverrideDll wmadmod native
    OverrideDll wmasf native

    rm -vf "$WINEPREFIX/drive_c/windows/$SYSDIR"/{qasf,wmasf,wmvcore}.dll

    RUN "$SCRIPT_DIR/wmp11/$wmf" /q

    SetWindowsVer $PREV_OSVER
}

Install_xaudio29()
{
    Heading "xaudio29"

    DownloadFileInternal xaudio29 xaudio2_9.dll 667787326dd6cc94f16e332fd271d15aabe1aba2003964986c8ac56de07d5b57

    cp -fv "$SCRIPT_DIR/xaudio29/xaudio2_9.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/xaudio2_9.dll"
    cp -fv "$SCRIPT_DIR/xaudio29/xaudio2_9.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/xaudio2_8.dll"

    OverrideDll xaudio2_9 native
    OverrideDll xaudio2_8 native
}

Install_lavfilters()
{
    Heading "LAVFilters"

    VER="0.77.2"
    FNAME="LAVFilters-$VER-Installer.exe"
    DownloadFile lavfilters $FNAME "https://github.com/Nevcairiel/LAVFilters/releases/download/$VER/$FNAME" 3bf333bae56f9856fb7db96ce2410df1da3958ac6a9fd5ac965d33c7af6f27d7

    Copy_WineVkd3dFiles

    RUN "$SCRIPT_DIR/lavfilters/$FNAME" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-

    RUN reg add "HKCU\\Software\\LAV\\Audio\\Formats" /f /t REG_DWORD /v wma /d 1
    RUN reg add "HKCU\\Software\\LAV\\Audio\\Formats" /f /t REG_DWORD /v wmapro /d 1
    RUN reg add "HKCU\\Software\\LAV\\Audio\\Formats" /f /t REG_DWORD /v wmalossless /d 1

    RUN reg add "HKCU\\Software\\LAV\\Video\\Output" /f /t REG_DWORD /v yuy2 /d 0
}


# ============================================================================

# note: VERBS is sorted to our preferred call sequence
VERBS="quartz2 mciqtz32 wmp11 mf lavfilters quartz_dx xaudio29"

RunActions()
{
    for item in $VERBS; do eval "do_$item=0"; done

    for item in $@; do
        VAL=$(eval "echo \$do_$item")
        if [ "$VAL" = 0 ]; then eval "do_$item=1";
        elif [ "$VAL" = 1 ]; then echo "duplicated verb: $item"; Quit;
        else echo "invalid verb: $item"; Quit; fi
    done

    CheckEnv
    GetWindowsVer
    GetSysDir

    for item in $VERBS; do [ $(eval "echo \$do_$item") = 1 ] && Install_${item}; done
}

if [ $# -gt 0 ]; then
    RunActions $@
else
    echo "Specify one or more of these verbs to install them:"
    echo $(echo $VERBS | tr ' ' '\n' | sort)
    echo
fi
