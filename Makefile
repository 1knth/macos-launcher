.PHONY: build test run install clean

build:
	bash scripts/build.sh

test:
	swift test

run: build
	pkill -x Prism 2>/dev/null || true
	open build/Prism.app

install:
	bash scripts/install.sh

clean:
	rm -rf build .build
