SETCOMPILER=
ifdef DC
	SETCOMPILER="--compiler=$(DC)"
endif

all: debug

debug:
	@dub build $(SETCOMPILER) --build=debug --quiet

release:
	@dub build $(SETCOMPILER) release --quiet

test:
	@dub test $(SETCOMPILER) --quiet

docs:
	@dub build $(SETCOMPILER) --build=ddox --quiet

clean:
	@dub clean
