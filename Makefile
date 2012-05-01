# See LICENSE file for license and copyright information

include config.mk
include common.mk

PROJECT    = zathura
OSOURCE    = $(wildcard *.c)
HEADER     = $(wildcard *.h)
HEADERINST = version.h document.h macros.h page.h types.h plugin-api.h annotations.h

ifneq (${WITH_SQLITE},0)
INCS   += $(SQLITE_INC)
LIBS   += $(SQLITE_LIB)
SOURCE = $(OSOURCE)
CPPFLAGS += -DWITH_SQLITE
else
SOURCE = $(filter-out database-sqlite.c,$(OSOURCE))
endif

ifneq ($(wildcard ${VALGRIND_SUPPRESSION_FILE}),)
VALGRIND_ARGUMENTS += --suppressions=${VALGRIND_SUPPRESSION_FILE}
endif

ifeq (,$(findstring -DZATHURA_PLUGINDIR,${CPPFLAGS}))
CPPFLAGS += -DZATHURA_PLUGINDIR=\"${PLUGINDIR}\"
endif
ifeq (,$(findstring -DGETTEXT_PACKAGE,${CPPFLAGS}))
CPPFLAGS += -DGETTEXT_PACKAGE=\"${PROJECT}\"
endif
ifeq (,$(findstring -DLOCALEDIR,${CPPFLAGS}))
CPPFLAGS += -DLOCALEDIR=\"${LOCALEDIR}\"
endif

OBJECTS  = $(patsubst %.c, %.o,  $(SOURCE))
DOBJECTS = $(patsubst %.c, %.do, $(SOURCE))

all: options ${PROJECT} po build-manpages

girara-version-check:
ifneq ($(GIRARA_VERSION_CHECK), 0)
	$(error "The minimum required version of girara is ${GIRARA_MIN_VERSION}")
endif
	$(QUIET)touch girara-version-check

options:
	@echo ${PROJECT} build options:
	@echo "CFLAGS  = ${CFLAGS}"
	@echo "LIBS    = ${LIBS}"
	@echo "DFLAGS  = ${DFLAGS}"
	@echo "CC      = ${CC}"

version.h: version.h.in config.mk
	$(QUIET)sed 's/ZVMAJOR/${ZATHURA_VERSION_MAJOR}/' < version.h.in | \
		sed 's/ZVMINOR/${ZATHURA_VERSION_MINOR}/' | \
		sed 's/ZVREV/${ZATHURA_VERSION_REV}/' | \
		sed 's/ZVAPI/${ZATHURA_API_VERSION}/' | \
		sed 's/ZVABI/${ZATHURA_ABI_VERSION}/' > version.h

%.o: %.c
	$(ECHO) CC $<
	@mkdir -p .depend
	$(QUIET)${CC} -c ${CPPFLAGS} ${CFLAGS} -o $@ $< -MMD -MF .depend/$@.dep

%.do: %.c
	$(ECHO) CC $<
	@mkdir -p .depend
	$(QUIET)${CC} -c ${CPPFLAGS} ${CFLAGS} ${DFLAGS} -o $@ $< -MMD -MF .depend/$@.dep

${OBJECTS}:  config.mk version.h girara-version-check
${DOBJECTS}: config.mk version.h girara-version-check

${PROJECT}: ${OBJECTS}
	$(ECHO) CC -o $@
	$(QUIET)${CC} ${SFLAGS} ${LDFLAGS} -o $@ ${OBJECTS} ${LIBS}

clean:
	$(QUIET)rm -rf ${PROJECT} ${OBJECTS} ${PROJECT}-${VERSION}.tar.gz \
		${DOBJECTS} ${PROJECT}-debug .depend ${PROJECT}.pc doc version.h \
		*gcda *gcno $(PROJECT).info gcov *.tmp \
		girara-version-check
	$(QUIET)make -C tests clean
	$(QUIET)make -C po clean

${PROJECT}-debug: ${DOBJECTS}
	$(ECHO) CC -o $@
	$(QUIET)${CC} ${LDFLAGS} -o $@ ${DOBJECTS} ${LIBS}

debug: ${PROJECT}-debug

${PROJECT}.pc: ${PROJECT}.pc.in config.mk
	$(QUIET)echo project=${PROJECT} > ${PROJECT}.pc
	$(QUIET)echo version=${VERSION} >> ${PROJECT}.pc
	$(QUIET)echo apiversion=${ZATHURA_API_VERSION} >> ${PROJECT}.pc
	$(QUIET)echo abiversion=${ZATHURA_ABI_VERSION} >> ${PROJECT}.pc
	$(QUIET)echo includedir=${INCLUDEDIR} >> ${PROJECT}.pc
	$(QUIET)echo plugindir=${PLUGINDIR} >> ${PROJECT}.pc
	$(QUIET)echo GTK_VERSION=${ZATHURA_GTK_VERSION} >> ${PROJECT}.pc
	$(QUIET)cat ${PROJECT}.pc.in >> ${PROJECT}.pc

valgrind: debug
	 $(QUIET)G_SLICE=always-malloc G_DEBUG=gc-friendly ${VALGRIND} ${VALGRIND_ARGUMENTS} \
		 ./${PROJECT}-debug

gdb: debug
	$(QUIET)cgdb ${PROJECT}-debug

test: ${OBJECTS}
	$(QUIET)make -C tests run

dist: clean build-manpages
	$(QUIET)mkdir -p ${PROJECT}-${VERSION}
	$(QUIET)mkdir -p ${PROJECT}-${VERSION}/tests
	$(QUIET)mkdir -p ${PROJECT}-${VERSION}/po
	$(QUIET)cp LICENSE Makefile config.mk common.mk README AUTHORS Doxyfile \
			${PROJECT}.1.rst ${PROJECT}rc.5.rst ${OSOURCE} ${HEADER} ${PROJECT}.pc.in \
			${PROJECT}.desktop version.h.in \
			${PROJECT}.1 ${PROJECT}rc.5 \
			${PROJECT}-${VERSION}
	$(QUIET)cp tests/Makefile tests/config.mk tests/*.c \
			${PROJECT}-${VERSION}/tests
	$(QUIET)cp po/Makefile po/*.po ${PROJECT}-${VERSION}/po
	$(QUIET)tar -cf ${PROJECT}-${VERSION}.tar ${PROJECT}-${VERSION}
	$(QUIET)gzip ${PROJECT}-${VERSION}.tar
	$(QUIET)rm -rf ${PROJECT}-${VERSION}

doc:
	$(QUIET)doxygen Doxyfile

gcov: clean
	$(QUIET)CFLAGS="${CFLAGS} -fprofile-arcs -ftest-coverage" LDFLAGS="${LDFLAGS} -fprofile-arcs" ${MAKE} $(PROJECT)
	$(QUIET)CFLAGS="${CFLAGS} -fprofile-arcs -ftest-coverage" LDFLAGS="${LDFLAGS} -fprofile-arcs" ${MAKE} -C tests run
	$(QUIET)lcov --directory . --capture --output-file $(PROJECT).info
	$(QUIET)genhtml --output-directory gcov $(PROJECT).info

po:
	$(QUIET)${MAKE} -C po

update-po:
	$(QUIET)${MAKE} -C po update-po

ifneq "$(wildcard ${RSTTOMAN})" ""
%.1 %.5: config.mk
	$(QUIET)sed "s/VERSION/${VERSION}/g" < $@.rst > $@.tmp
	$(QUIET)${RSTTOMAN} $@.tmp > $@
	$(QUIET)rm $@.tmp

${PROJECT}.1: ${PROJECT}.1.rst
${PROJECT}rc.5: ${PROJECT}rc.5.rst

build-manpages: ${PROJECT}.1 ${PROJECT}rc.5
else
build-manpages:
endif

install-manpages: build-manpages
	$(ECHO) installing manual pages
	$(QUIET)mkdir -m 755 -p ${DESTDIR}${MANPREFIX}/man1 ${DESTDIR}${MANPREFIX}/man5
ifneq "$(wildcard ${PROJECT}.1)" ""
	$(QUIET)install -m 644 ${PROJECT}.1 ${DESTDIR}${MANPREFIX}/man1
endif
ifneq "$(wildcard ${PROJECT}rc.5)" ""
	$(QUIET)install -m 644 ${PROJECT}rc.5 ${DESTDIR}${MANPREFIX}/man5
endif

install-headers: ${PROJECT}.pc
	$(ECHO) installing header files
	$(QUIET)mkdir -m 755 -p ${DESTDIR}${INCLUDEDIR}/${PROJECT}
	$(QUIET)install -m 644 ${HEADERINST} ${DESTDIR}${INCLUDEDIR}/${PROJECT}
	$(ECHO) installing pkgconfig file
	$(QUIET)mkdir -m 755 -p ${DESTDIR}${LIBDIR}/pkgconfig
	$(QUIET)install -m 644 ${PROJECT}.pc ${DESTDIR}${LIBDIR}/pkgconfig

install: all install-headers install-manpages
	$(ECHO) installing executable file
	$(QUIET)mkdir -m 755 -p ${DESTDIR}${PREFIX}/bin
	$(QUIET)install -m 755 ${PROJECT} ${DESTDIR}${PREFIX}/bin
	$(QUIET)mkdir -m 755 -p ${DESTDIR}${DESKTOPPREFIX}
	$(ECHO) installing desktop file
	$(QUIET)install -m 644 ${PROJECT}.desktop ${DESTDIR}${DESKTOPPREFIX}
	$(MAKE) -C po install

uninstall-headers:
	$(ECHO) removing header files
	$(QUIET)rm -rf ${DESTDIR}${INCLUDEDIR}/${PROJECT}
	$(ECHO) removing pkgconfig file
	$(QUIET)rm -f ${DESTDIR}${LIBDIR}/pkgconfig/${PROJECT}.pc

uninstall: uninstall-headers
	$(ECHO) removing executable file
	$(QUIET)rm -f ${DESTDIR}${PREFIX}/bin/${PROJECT}
	$(ECHO) removing manual pages
	$(QUIET)rm -f ${DESTDIR}${MANPREFIX}/man1/${PROJECT}.1
	$(QUIET)rm -f ${DESTDIR}${MANPREFIX}/man5/${PROJECT}rc.5
	$(ECHO) removing desktop file
	$(QUIET)rm -f ${DESTDIR}${DESKTOPPREFIX}/${PROJECT}.desktop
	$(MAKE) -C po uninstall

-include $(wildcard .depend/*.dep)

.PHONY: all options clean doc debug valgrind gdb dist doc install uninstall test \
	po install-headers uninstall-headers update-po install-manpages build-manpages
