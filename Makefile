ARCHS = arm64
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = s2chams
s2chams_FILES = src/main.mm
s2chams_CFLAGS = -fobjc-arc -Ivendor/dobby/include -I. -std=c++17 -O2 -Wno-unused-function -Wno-module-import-in-extern-c
s2chams_LDFLAGS = -Lvendor/dobby -ldobby -framework UIKit -framework Foundation
s2chams_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk
