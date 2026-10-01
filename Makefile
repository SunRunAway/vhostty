.PHONY: all app ghostty run install clean

all: app

ghostty:
	scripts/build-ghostty.sh

app:
	scripts/bundle.sh

run: app
	open build/Seance.app

install: app
	rm -rf /Applications/Seance.app
	cp -R build/Seance.app /Applications/Seance.app
	@echo "Installed to /Applications/Seance.app"

clean:
	rm -rf .build build/Seance.app
