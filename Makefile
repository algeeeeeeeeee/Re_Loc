TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Reloc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RelocEnglish
RelocEnglish_FILES = Tweak.x
RelocEnglish_FRAMEWORKS = Foundation UIKit
RelocEnglish_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/tweak.mk
