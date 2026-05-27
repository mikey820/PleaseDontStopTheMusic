TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PleaseDontStopTheMusic

PleaseDontStopTheMusic_FILES = ../Tweak.x
PleaseDontStopTheMusic_CFLAGS = -fobjc-arc
PleaseDontStopTheMusic_FRAMEWORKS = AVFoundation
PleaseDontStopTheMusic_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
