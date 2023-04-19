#!/bin/bash

echo "WMP11 install script (v2023-04-19)"
echo ""

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

Quit() { echo ""; exit; }

CheckEnv()
{
    # check for wine. it can be defined in $WINE or found in $PATH
    if [ "$WINE" = "" ]; then
        WINE="wine"
    fi

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
    if ! $(WINEDEBUG="-all" WINEARCH=$ARCH $WINE wineboot -e); then Quit; fi
}

RUN()
{
    echo "[run] $WINE $@"
    WINEDEBUG="-all" $WINE $@
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
    if [[ "$REQVER" = "winxp" && "$ARCH" = "win64" ]]; then REQVER="winxp64"; fi

    RUN winecfg -v "$REQVER"
    GetWindowsVer
}

OverrideDll()
{
    RUN reg add "HKCU\\Software\\Wine\\DllOverrides" /f /t REG_SZ  /v $1 /d $2
}

Hash_SHA256()
{
    HASH=$(sha256sum $1 | sed -e "s/ .*//" | tr -d '\n')
    if [ "$HASH" != $2 ]; then
        echo "... hash mismatch on $1"
        echo "download hash $HASH"
        echo "expected hash $2"
        Quit
    fi
}

# ============================================================================

Download_WMP11()
{
    DLFILE="$SCRIPT_DIR/$1"

    # download installer if we don't have it yet
    if [ ! -f "$DLFILE" ]; then
        WGET_ARGS="--progress=bar"
        (wget $WGET_ARGS -O "$DLFILE" "https://raw.githubusercontent.com/b-fission/vn_winestuff/master/wmp11/$1")
        if [ $? -ne 0 ]; then
            echo "An error occurred while downloading $1"
            rm "$DLFILE"
            Quit
        fi
    fi

    # file hash must match, otherwise quit
    if [ -f "$DLFILE" ]; then
        Hash_SHA256 "$DLFILE" $2
    else
        echo "$1 is not found, cannot continue."
    fi
}

Install_WMP11()
{
    PREV_OSVER=$OSVER

    SetWindowsVer winxp
    OverrideDll qasf native
    RUN "$SCRIPT_DIR/$wmf" /q

    SetWindowsVer $PREV_OSVER
}


CheckEnv
GetWindowsVer

case $ARCH in
    win32) wmf="wmfdist11.exe";    validhash=ddfea7b588200d8bb021dbf1716efb9f63029a0dd016d4c12db89734852e528d;;
    win64) wmf="wmfdist11-64.exe"; validhash=eba63fa648016f3801e503fc91d9572b82aeb0409e73c27de0b4fbc51e81e505;;
    *) Quit
esac

Download_WMP11 $wmf $validhash
Install_WMP11
