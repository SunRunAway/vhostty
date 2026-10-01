.PHONY: all app ghostty run install clean

all: app

ghostty:
	scripts/build-ghostty.sh

app:
	scripts/bundle.sh

run: app
	open build/Vhostty.app

install: app
	rm -rf /Applications/Vhostty.app
	cp -R build/Vhostty.app /Applications/Vhostty.app
	@echo "Installed to /Applications/Vhostty.app"

clean:
	rm -rf .build build/Vhostty.app
