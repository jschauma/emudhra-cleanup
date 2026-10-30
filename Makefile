NAME=emudhra-cleanup

PREFIX?=/usr/local
OS!=uname

help:
	@echo "The following targets are available:"
	@echo "doc        format man page into .txt"
	@echo "install    install ${NAME} into ${PREFIX}"
	@echo "readme     update README.md with the formatted man page"
	@echo "uninstall  uninstall ${NAME} from ${PREFIX}"

doc: doc/${NAME}.1.txt

doc/${NAME}.1.txt: doc/${NAME}.1
	mandoc -c -O width=80 $? | col -b >$@

readme: doc
	sed -n -e '/^NAME/!p;//q' README.md >.readme
	sed -n -e '/^NAME/,$$p' -e '/author/q' doc/${NAME}.1.txt >>.readme
	echo '```' >>.readme
	mv .readme README.md

install:
	mkdir -p ${PREFIX}/bin ${PREFIX}/share/man/man1
	install -c -m 0555 src/${NAME}.sh ${PREFIX}/bin/${NAME}
	install -c -m 0555 doc/${NAME}.1 ${PREFIX}/share/man/man1/${NAME}.1

uninstall:
	rm -f ${PREFIX}/bin/${NAME} ${PREFIX}/share/man/man1/${NAME}.1
