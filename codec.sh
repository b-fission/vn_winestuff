#!/bin/bash

echo
echo "Helper script to install codecs for VNs on wine (v2023-04-23)"
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
    WINEDEBUG="-all" WINEARCH=$ARCH $WINE wineboot -e || Quit
}

RUN()
{
    echo "[run] $WINE $@"
    WINEDEBUG="-all" $WINE $@

    if [ $? -ne 0 ]; then echo "some kind of error occurred."; Quit; fi
}

GetWindowsVer()
{
    OSVER=$(WINEDEBUG="-all" $WINE winecfg -v | tr -d '\r')
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

    OverrideDll winegstreamer ""
    for DLL in $OVERRIDE_DLL; do OverrideDll $DLL native; done

    RUN "c:/windows/$SYSDIR/reg.exe" import "$WORKDIR/temp/mf.reg"
    RUN "c:/windows/$SYSDIR/reg.exe" import "$WORKDIR/temp/wmf.reg"

    for DLL in $REGISTER_DLL; do RUN regsvr32 "c:/windows/$SYSDIR/$DLL.dll"; done

    # install 64-bit components .... not needed yet. skipping this part!
    if [ 1 -eq 0 ]; then
        DownloadFileInternal mf mf64.zip 000000

        unzip -o -q -d "$WORKDIR/temp" "$WORKDIR/mf64.zip" || Quit;
        cp -vf "$WORKDIR/temp/system32"/* "$WINEPREFIX/drive_c/windows/system32"

        for DLL in $REGISTER_DLL; do RUN regsvr32 "c:/windows/system32/$DLL.dll"; done

        RUN "c:/windows/system32/reg.exe" import "$WORKDIR/temp/mf.reg"
        RUN "c:/windows/system32/reg.exe" import "$WORKDIR/temp/wmf.reg"
    fi

    # cleanup
    rm -fr "$WORKDIR/temp"
}

Install_quartz2()
{
    Heading "quartz2"

    DownloadFileInternal quartz2 quartz2.dll fa52a0d0647413deeef57c5cb632f73a97a48588c16877fc1cc66404c3c21a2b

    cp -fv "$SCRIPT_DIR/quartz2/quartz2.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/quartz2.dll"
    RUN regsvr32 quartz2.dll

    OverrideDll winegstreamer ""

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
    OverrideDll qasf native
    OverrideDll winegstreamer ""

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

    RUN "$SCRIPT_DIR/lavfilters/$FNAME" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-

    RUN reg add "HKCU\\Software\\LAV\\Audio\\Formats" /f /t REG_DWORD /v wmalossless /d 1
}


# ============================================================================

# note: VERBS is sorted to our preferred call sequence
VERBS="quartz2 mciqtz32 wmp11 mf lavfilters xaudio29"

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
