##
##  LibreSignage makefile
##

NPMBIN := $(shell ./build/scripts/npmbin.sh)

# Note: This makefile assumes that $(ROOT) always has a trailing
# slash. (which is the case when using the makefile $(dir ...)
# function) Do not use the shell dirname command here as that WILL
# break things since it doesn't add the trailing slash to the path.
ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

SASS_IPATHS := $(ROOT) $(ROOT)src/common/css
SASSFLAGS := --sourcemap=none --no-cache

VERBOSE ?= Y     # Verobose log output.
NOHTMLDOCS ?= N  # Don't generate HTML docs.
INST ?= ""       # Installation config path.

# LibreSignage build dependencies. Note that apache is excluded
# since checking whether it's installed usually requires root.
DEPS := php7.0 pandoc sass npm

# Production libraries.
LIBS := $(filter-out \
	$(shell echo "$(ROOT)"|sed 's:/$$::g'), \
	$(shell npm ls --prod --parseable|sed 's/\n/ /g') \
)

# Non-compiled sources.
SRC_NO_COMPILE := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -path 'src/api/endpoint/*' -prune \) \
	-o \( \
		-type f ! -name '*.swp' \
		-a -type f ! -name '*.save' \
		-a -type f ! -name '.\#*' \
		-a -type f ! -name '\#*\#*' \
		-a -type f ! -name '*~' \
		-a -type f ! -name '*.js' \
		-a -type f ! -name '*.scss' \
		-a -type f ! -name '*.rst' \
		-a -type f ! -name 'config.php' -print \
	\) \
)

# RST sources.
SRC_RST := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o -type f -name '*.rst' -print \
) README.rst CONTRIBUTING.rst

# SCSS sources.
SRC_SCSS := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o -type f -name '*.scss' -a ! -name '_*' -print \
)

# JavaScript sources.
SRC_JS := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -name 'main.js' -print \) \
)

# API endpoint sources.
SRC_ENDPOINT := $(shell find src/api/endpoint \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -name '*.php' -print \) \
)

status = \
	if [ "`echo '$(VERBOSE)'|cut -zc1|\
		tr '[:upper:]' '[:lower:]'`" = "y" ]; then \
		echo "$(1): $(2) >> $(3)"|tr -s ' '|sed 's/^ *$///g'; \
	fi
makedir = mkdir -p $(dir $(1))

ifeq ($(NOHTMLDOCS),$(filter $(NOHTMLDOCS),y Y))
$(info [INFO] Won't generate HTML documentation.)
endif

.PHONY: initchk configure dirs server js css api \
		config libs docs htmldocs install utest \
		clean realclean LOC
.ONESHELL:

all:: server docs htmldocs js css api config libs; @:

server:: initchk $(subst src,dist,$(SRC_NO_COMPILE)); @:
js:: initchk $(subst src,dist,$(SRC_JS)); @:
api:: initchk $(subst src,dist,$(SRC_ENDPOINT)); @:
config:: initchk dist/common/php/config.php; @:
libs:: initchk dist/libs; @:
docs:: initchk $(addprefix dist/doc/rst/,$(notdir $(SRC_RST))) dist/doc/rst/api_index.rst; @:
htmldocs:: initchk $(addprefix dist/doc/html/,$(notdir $(SRC_RST:.rst=.html))); @:
css:: initchk $(subst src,dist,$(SRC_SCSS:.scss=.css)); @:
libs:: initchk $(subst $(ROOT)node_modules/,dist/libs/,$(LIBS)); @:

# Copy over non-compiled, non-PHP sources.
$(filter-out %.php,$(subst src,dist,$(SRC_NO_COMPILE))):: dist%: src%
	@:
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Copy over normal PHP files and check the PHP syntax.
$(filter %.php,$(subst src,dist,$(SRC_NO_COMPILE))):: dist%: src%
	@:
	php -l $< > /dev/null
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Copy API endpoint PHP files and generate corresponding docs.
$(subst src,dist,$(SRC_ENDPOINT)):: dist%: src%
	@:
	php -l $< > /dev/null

	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		# Generate reStructuredText documentation.
		mkdir -p dist/doc/rst
		mkdir -p dist/doc/html
		$(call status,\
			gendoc.sh,\
			<generated>,\
			dist/doc/rst/$(notdir $(@:.php=.rst))\
		)
		./build/scripts/gendoc.sh $(INST) $@ dist/doc/rst/

		# Compile rst docs into HTML.
		$(call status,\
			pandoc,\
			dist/doc/rst/$(notdir $(@:.php=.rst)),\
			dist/doc/html/$(notdir $(@:.php=.html))\
		)
		pandoc -f rst -t html \
			-o dist/doc/html/$(notdir $(@:.php=.html)) \
			dist/doc/rst/$(notdir $(@:.php=.rst))
	fi

# Generate the API endpoint documentation index.
dist/doc/rst/api_index.rst:: $(SRC_ENDPOINT)
	@:
	$(call status,makefile,<generated>,$@)
	$(call makedir,$@)

	@. build/scripts/conf.sh
	echo "LibreSignage API documentation (Ver: $$ICONF_API_VER)" > $@
	echo '########################################################' >> $@
	echo '' >> $@
	echo "This document was automatically generated by the"\
		"LibreSignage build system on `date`." >> $@
	echo '' >> $@
	for f in $(SRC_ENDPOINT); do
		echo "\``basename $$f` </doc?doc=`basename -s '.php' $$f`>\`_" >> $@
		echo '' >> $@
	done

	# Compile into HTML.
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$(subst /rst/,/html/,$($:.rst=.html)),$@)
		$(call makedir,$(subst /rst/,/html/,$@))
		pandoc -f rst -t html -o $(subst /rst/,/html/,$(@:.rst=.html)) $@
	fi

# Copy and prepare 'config.php'.
dist/common/php/config.php:: src/common/php/config.php
	@:
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@
	$(call status,prep.sh,<inplace>,$@)
	./build/scripts/prep.sh $(INST) $@
	php -l $@ > /dev/null

# Copy over README.rst.
dist/doc/rst/README.rst:: README.rst
	@:
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Copy over CONTRIBUTING.rst.
dist/doc/rst/CONTRIBUTING.rst:: CONTRIBUTING.rst
	@:
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Copy over RST sources.
dist/doc/rst/%.rst:: src/doc/rst/%.rst
	@:
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Compile RST sources into HTML.
dist/doc/html/%.html:: src/doc/rst/%.rst
	@:
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$<,$@)
		$(call makedir,$@)
		pandoc -o $@ -f rst -t html $<
	fi

# Compile README.rst
dist/doc/html/README.html:: README.rst
	@:
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$<,$@)
		$(call makedir,$@)
		pandoc -o $@ -f rst -t html $<
	fi

# Compile CONTRIBUTING.rst
dist/doc/html/CONTRIBUTING.html:: CONTRIBUTING.rst
	@:
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$<,$@)
		$(call makedir,$@)
		pandoc -o $@ -f rst -t html $<
	fi

# Generate JavaScript deps.
dep/%/main.js.dep: src/%/main.js
	@:
	$(call status,deps-js,$<,$@)
	$(call makedir,$@)
	echo "$(subst src,dist,$<):: `$(NPMBIN)/browserify --list $<|\
		tr '\n' ' '|\
		sed 's:$(ROOT)::g'`" > $@

	# Make the target silent.
	echo "\t@:" >> $@

	# Output log info.
	echo "\t\$$(call status,"\
		"compile-js,"\
		"$<,"\
		"$(subst src,dist,$<))" >> $@

	# Create directory.
	echo "\t\$$(call makedir,$(subst src,dist,$<))" >> $@

	# Process with browserify.
	echo "\t$(NPMBIN)/browserify $< -o $(subst src,dist,$<)" >> $@

# Generate SCSS deps.
dep/%.scss.dep: src/%.scss
	@:
	# Don't create deps for partials.
	if [ ! "`basename '$(<)' | cut -c 1`" = "_" ]; then
		$(call status,deps-scss,$<,$@)
		$(call makedir,$@)
		echo "$(subst src,dist,$(<:.scss=.css)):: $< `\
			./build/scripts/sassdep.py -l $< $(SASS_IPATHS)|\
			sed 's:$(ROOT)::g'`" > $@

		# Make the target silent.
		echo "\t@:" >> $@

		# Output log info.
		echo "\t\$$(call status,"\
			"compile-scss,"\
			"$<,"\
			"$(subst src,dist,$(<:.scss=.css)))" >> $@

		# Create directory.
		echo "\t\$$(call makedir,$(subst src,dist,$<))" >> $@

		# Compile with sass.
		echo "\tsass"\
			"$(addprefix -I,$(SASS_IPATHS))"\
			"$(SASSFLAGS)"\
			"$<"\
			"$(subst src,dist,$(<:.scss=.css))" >> $@

		# Process with postcss.
		echo "\t$(NPMBIN)/postcss"\
			"$(subst src,dist,$(<:.scss=.css))"\
			"--config postcss.config.js"\
			"--replace"\
			"--no-map" >> $@
	fi

# Copy production node modules to 'dist/libs/'.
dist/libs/%:: node_modules/%
	@:
	mkdir -p $@
	$(call status,cp,$<,$@)
	cp -Rp $</* $@

install:; @./build/scripts/install.sh $(INST)

utest:; @./utests/api/main.py

clean:
	rm -rf dist
	rm -rf dep
	rm -rf `find . -type d -name '__pycache__'`
	rm -rf `find . -type d -name '.sass-cache'`
	rm -f *.log

realclean:
	@:

	$(call status,real-clean,various,remove)
	rm -f build/*.iconf
	rm -rf build/link
	rm -rf node_modules
	rm -f package-lock.json

	# Remove temporary nano files.
	$(call status,nano-clean,tmp,remove)
	TMP="`find . \
		\( -type d -path './node_modules/*' -prune \) \
		-o \( \
			-type f -name '*.swp' -printf '%p ' \
			-o  -type f -name '*.save' -printf '%p ' \
		\)`"
	if [ ! -z "$$TMP" ]; then
		rm -f $$TMP
	fi

	# Remove temporary emacs files.
	$(call status,emacs-clean,tmp,remove)
	TMP="`find . \
		\( -type d -path './node_modules/*' -prune \) \
		-o \( \
			 -type f -name '\#*\#*' -printf '%p ' \
			-o -type f -name '*~' -printf '%p ' \
		\)`"
	if [ ! -z "$$TMP" ]; then
		rm -f $$TMP
	fi


# Count the lines of code in LibreSignage.
LOC:
	@:
	echo 'Lines Of Code: '
	wc -l `find . \
		\( \
			-path "./dist/*" -o \
			-path "./utests/api/.mypy_cache/*" -o \
			-path "./node_modules/*" \
		\) -prune \
		-o -name ".#*" \
		-o -name "*.py" -print \
		-o -name "*.php" -print \
		-o -name "*.js" -print \
		-o -name "*.html" -print \
		-o -name "*.css" -print \
		-o -name "*.scss" -print \
		-o -name "*.sh" -print \
		-o ! -name 'package-lock.json' -name "*.json" -print \
		-o -name "*.py" -print`

LOD:
	@:
	echo '[INFO] Make sure your 'dist/' is up to date!'
	echo '[INFO] Lines Of Documentation: '
	wc -l `find dist -type f -name '*.rst'`

configure:
	@:
	./build/scripts/configure.sh

initchk:
	@:
	./build/scripts/ldiconf.sh $(INST)

	# Check that the require dependencies are installed.
	for d in $(DEPS); do
		if [ -z "`which $$d`" ]; then
			echo "[ERROR] Missing dependency: $$d."
			exit 1
		fi
	done

%:
	@:
	echo "[INFO]: Ignore $@"

ifeq (,$(filter LOC LOD clean realclean configure initchk,$(MAKECMDGOALS)))
$(info [INFO] Include dependency makefiles.)
-include $(subst src,dep,$(SRC_JS:.js=.js.dep))\
		$(subst src,dep,$(SRC_SCSS:.scss=.scss.dep))
endif
