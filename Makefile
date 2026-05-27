all::
	$(MAKE) -C rootless package FINALPACKAGE=1
	$(MAKE) -C rootful package FINALPACKAGE=1
	$(MAKE) -C jailed
	cp jailed/.theos/obj/debug/PleaseDontStopTheMusic.dylib jailed/PleaseDontStopTheMusic.dylib 2>/dev/null || true

clean::
	$(MAKE) -C rootless clean
	$(MAKE) -C rootful clean
	$(MAKE) -C jailed clean
