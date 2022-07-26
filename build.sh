#!/bin/bash -e

REQUIRED_BOOTSTRAP_VERSION=210

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export ROOT_DIR=$PWD/..
export SOURCE_DIR=$PWD

# setup options
OPT_EMULATE=no
OPT_CLEAN=no
PROJECT=none
RESOLUTION=none
PREFIX=/home/tronxi/workspace/bqeReaderSDK-5.0.2
PRIVATE=../qbookapp-private
OPT_CPPOPTO0=no
DEBUG_OPTS=yes
FAKEWIFI=no
OPT_FREESCALE=no
OPT_HACKERS=no
DISABLE_ADOBE=no

while [ $# -gt 0 ]
do
        case $1 in
        -clean) OPT_CLEAN=yes ;;
        -emulate) OPT_EMULATE=yes ;;
        -prefix) PREFIX="$2"; shift ;;
        -private) PRIVATE="$2"; shift ;;
        -disable_opt) OPT_CPPOPTO0=yes ;;
        -massproduction) DEBUG_OPTS=no ;;
        -800) RESOLUTION=800 ;;
        -1024) RESOLUTION=1024 ;;
        -fakewifi) FAKEWIFI=yes ;;
        -mx) OPT_FREESCALE=yes ;;
        -hackers) OPT_HACKERS=yes ;;
        -disable_adobe) DISABLE_ADOBE=yes ;;
        (--) shift; break;;
        (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
#       (*) break;;
        esac
        shift
done

# generate hg version strings
HG_REV=`git rev-parse HEAD | cut -c1-6`
HG_BRANCH=`git branch`
BUILD_DATE=`eval date +%Y%m%d_%H%M`
export PRIVATE=$PRIVATE
# set environment
mkdir -p $SOURCE_DIR/obj || true
if [ "$OPT_EMULATE" == "yes" ]; then
    export QTDIR=/usr/share/qt
    export PLATFORM=emu
    export ROOTFS=$PREFIX/x86-rootfs-devel
    export CC=gcc
    export CXX=g++
    if [ $FAKEWIFI != "no" ]; then
	export FAKE_WIFI=1
    fi
    if [ -f /etc/fedora-release ]; then
	export QMAKESPEC=/usr/lib/qt4/mkspecs/linux-g++-32/
	export QT_DEV_PATH=/usr/
	# Newest compiler requires explicit linking
	export EXTRA_LIBS=" -ldl -lfreetype -lpng -lz -lpng10 -lzip" 
    else
	export QT_DEV_PATH=/usr/share/qt4
    fi
else

    export ROOTFS=$PREFIX/mx508-rootfs-devel
    export PLATFORM=mx508
    export QTDIR=$ROOTFS/usr
    export CC=/usr/bin/arm-linux-gnueabi-gcc
    export CXX=/usr/bin/arm-linux-gnueabi-g++
    export QMAKESPEC=$QTDIR/mkspecs/default

fi

# Check bootstrap version
if [ -f $ROOTFS/.version ]; then
        BOOTSTRAP_VERSION=`head -1 $ROOTFS/.version`
        BQBUILD_HGVERSION=`tail -1 $ROOTFS/.version`
else
        BOOTSTRAP_VERSION=0
        BQBUILD_HGVERSION="NA"
fi

if [ $BOOTSTRAP_VERSION -lt $REQUIRED_BOOTSTRAP_VERSION ]; then
        echo "QBookApp requires a bootstrap version >= $REQUIRED_BOOTSTRAP_VERSION and current version is $BOOTSTRAP_VERSION"
        echo "Please, update your bqbuild scripts, re-generate the bootstrap and update whole ROOTFS in the DEVICE"
        exit 1
fi
ROOTFS_VERSION=$BOOTSTRAP_VERSION-$BQBUILD_HGVERSION


if [ "$DEBUG_OPTS" == "no" ]; then
    export DEFINES='QT_NO_DEBUG_OUTPUT QT_NO_WARNING_OUTPUT'
fi

if [ -n "$HACKERS_EDITION" ]; then
    OPT_HACKERS=yes
fi

if [ "$OPT_HACKERS" == "yes" ]; then
    export HACKERS_EDITION='1'
fi

if [ "$DISABLE_ADOBE" == "yes" ]; then
    export DISABLE_ADOBE_SDK='1'
fi



### Select project

#keep it until the end of refactoring
export PROJECT=ELF


# Set C++ compilation optimization
if [ "$OPT_CPPOPTO0" == "yes" ]; then # Disable C++ compilation optimization
    export CPP_OPTIM=CPP_OPT_O0
else
    export CPP_OPTIM=CPP_OPT_O2
fi

if [ "$OPT_CLEAN" == "yes" ]; then
    echo "Creating makefile for cleaning..."
    qmake || exit $?
    echo "Cleaning..."
    make distclean > /dev/null 2>&1 || true
    cd ConnectionManager
    qmake || exit $?
    echo "Cleaning..."
    make distclean > /dev/null 2>&1 || true
    cd ..

    cd bqUtils
    qmake || exit $?
    echo "Cleaning..."
    make distclean > /dev/null 2>&1 || true
    cd ..

    cd model
    qmake || exit $?
    echo "Cleaning..."
    make distclean > /dev/null 2>&1 || true
    cd ..

    if [ "$OPT_HACKERS" == "no" ]; then
        if [ -f $PRIVATE/bqClientServices/bqClientServices.pro ]; then
            cd $PRIVATE/bqClientServices
            qmake || exit $?
            echo "Cleaning..."
            make distclean > /dev/null 2>&1 || true
            cd ..

            cd syncHelper
            qmake || exit $?
            echo "Cleaning..."
            make distclean > /dev/null 2>&1 || true
            cd ..
        else
            echo "ERROR: You need private repository for complete application build, use -hackers for build without services"
            exit 1
        fi
    fi

fi

cd $SOURCE_DIR

cd ConnectionManager
qmake || exit $?
cd lib
qmake || exit $?
cd ../test
qmake || exit $?
cd ../connect
qmake || exit $?
cd ../offline
qmake || exit $?
cd ..
make $MAKEFLAGS || exit $?
cd ..

# Libreria bqUtils
cd bqUtils
qmake || exit $?
make $MAKEFLAGS || exit $?
cd ..

# Libreria Modelo
cd model
qmake || exit $?
make $MAKEFLAGS || exit $?
cd ..

if [ "$OPT_HACKERS" == "no" ]; then
    if [ -f $PRIVATE/bqClientServices/bqClientServices.pro ]; then
	# Libreria bqClientServices
        cd $PRIVATE/bqClientServices

        # generate hg version strings for services
        HG_VER_SERVICES=`hg id | cut -c1-6`

	qmake || exit $?
	make $MAKEFLAGS || exit $?
	cd ..

	# Libreria syncHelper
	cd syncHelper
	qmake || exit $?
	make $MAKEFLAGS || exit $?
	cd ..
    else
        echo "ERROR: You need private repository for complete application build, use -hackers for build without services"
        exit 1
    fi
else
    HG_VER_SERVICES="NA"
fi

cd $SOURCE_DIR
if [ -f hgversion.h ]; then
    OLDHG_VER=`grep HG_VERSION hgversion.h | sed -e 's/#define HG_VERSION "\([^_]*\).*"$/\1/'`
    OLDROOTFS_VERSION=`grep ROOTFS_VERSION hgversion.h  | sed -e 's/#define ROOTFS_VERSION "\(.*\)"$/\1/'`
    OLDHG_VER_SERVICES=`grep HG_SERVICES_VERSION hgversion.h | sed -e 's/#define HG_SERVICES_VERSION "\([^_]*\).*"$/\1/'`
    if [ X$OLDHG_VER != X$HG_REV ]; then
        echo "hg version has been changed, needs to be regenerated"
        rm -f hgversion.h
    elif [ X$OLDROOTFS_VERSION != X$ROOTFS_VERSION ]; then
        echo "bootstrap version has been changed, needs to be regenerated"
        rm -f hgversion.h
    elif [ X$OLDHG_VER_SERVICES != X$HG_VER_SERVICES ]; then
        echo "hg version for services has been changed, needs to be regenerated"
        rm -f hgversion.h
    fi
fi

if [ ! -f hgversion.h ]; then
        echo "Creating new hgversion.h"
        echo "#define HG_VERSION \""$HG_REV"_"$HG_BRANCH"_"$BUILD_DATE"\"" >> hgversion.h
        echo "#define ROOTFS_VERSION \"$ROOTFS_VERSION\"" >> hgversion.h
        echo "#define HG_SERVICES_VERSION \"$HG_VER_SERVICES\"" >> hgversion.h
fi

qmake || exit $?
make $MAKEFLAGS || exit $?
