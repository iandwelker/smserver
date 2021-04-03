#!/bin/bash

pn () {
	{ [ $# -gt 1 ] && [[ "${2}" == "-n" ]] && echo -en "${1}" >&3; } || echo -e "${1}" >&3
}

leave() {
	[ -d "${ROOTDIR}/package/SMServer.xcarchive" ] && rm -rf "${ROOTDIR}/package/SMServer.xcarchive"
	ls ./*.pem && rm key.pem cert.pem
	if ! [ "$kep" = true ]
	then
		[ -d "${ROOTDIR}/package/Payload" ] && rm -r "${ROOTDIR}/package/Payload"
		[ -d "${ROOTDIR}/package/deb/Applications" ] && rm -r "${ROOTDIR}/package/deb/Applications"
	fi

	if [ -d "${html_tmp}" ]
	then
		rm -r "${html_dir}" >&3
		mv "${html_tmp}" "${html_dir}" >&3
	fi

	exit
}

err () {
	pn "\033[31;1mERROR:\033[0m ${1}"
	leave
}

OLDDIR="$(pwd)"
ROOTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
[[ "$OLDDIR" == "$ROOTDIR" ]] && ROOTDIR="."

html_dir="${ROOTDIR}/src/SMServer/html"
html_tmp="${ROOTDIR}/src/SMServer/tmp_html"

vers=$(grep "Version" "${ROOTDIR}/package/deb/DEBIAN/control" | cut -d " " -f2)
new=false
deb=false
ipa=false
vbs=false
hlp=false
kep=false
min=false

stty -echoctl
trap 'leave' SIGINT

for arg in "$@"
do
	ng=$(echo "$arg" | cut -d "-" -f2-)
	if [[ "${ng:0:1}" == "-" ]]
	then
		[[ "${ng}" == "-new" ]] && new=true
		[[ "${ng}" == "-deb" ]] && deb=true
		[[ "${ng}" == "-ipa" ]] && ipa=true
		[[ "${ng}" == "-help" ]] && hlp=true
		[[ "${ng}" == "-keep" ]] && kep=true
		[[ "${ng}" == "-verbose" ]] && vbs=true
		[[ "${ng}" == "-minify" ]] && min=true
	else
		for ((i=0; i<${#ng}; i++))
		do
			[[ "${ng:$i:1}" == "n" ]] && new=true
			[[ "${ng:$i:1}" == "d" ]] && deb=true
			[[ "${ng:$i:1}" == "i" ]] && ipa=true
			[[ "${ng:$i:1}" == "v" ]] && vbs=true
			[[ "${ng:$i:1}" == "h" ]] && hlp=true
			[[ "${ng:$i:1}" == "k" ]] && kep=true
			[[ "${ng:$i:1}" == "m" ]] && min=true
		done
	fi
done

{ [ "$vbs" = true ] && exec 3>&1; } || exec 3>&1 &>/dev/null

[[ "$(uname)" == "Darwin" ]] || err "This can only be run on MacOS"

if [ "$hlp" = true ] || { [ "$deb" != true ] && [ "$ipa" != true ] && [ "$new" != true ]; }
then
	pn "
    usage: ./make.sh -hndivk

    \033[1mOptions\033[0m:
        -h, --help    : Shows this help message; ignores all other options
        -n, --new     : Runs processes that only need to happen once, specifically creating a certificate
                        and adding support swift files. You must run this at least once after cloning the
                        repo or else it won't build.
        -d, --deb     : Builds a .deb. Requires either the command line utility \033[1mdpkg\033[0m, or a jailbroken
                        iDevice on the local network to ssh into to create the archive
        -i, --ipa     : Builds a .ipa
        -v, --verbose : Runs verbose; doesn't hide any output
        -k, --keep    : Don't remove extracted \033[1mSMServer.app\033[0m files when cleaning up
		-m, --minify  : Minify css & html file when compiling assets using minify (\033[1mbrew install tdewolff/tap/minify\033[0m)
    "
	exit
fi

! command -v xcodebuild &>/dev/null && err "Please install xcode command line tools"

[ "$new" = true ] && ! command -v openssl &> /dev/null && err "Please install \033[1mopenssl\033[0m (required to build new certificates)"
[ "$deb" = true ] && ! command -v dpkg &>/dev/null && err "Please install dpkg to create deb pagkage"

ls -A "${ROOTDIR}"/libsmserver/* || err "It looks like you haven't yet set up this repository's submodules. Please run \033[1mgit submodule init && git submodule update --remote\033[0m and try again."

[ -z ${DEV_CERT+x} ] && DEV_CERT=$(security find-identity -v -p codesigning | head -n1 | cut -d '"' -f2)

if [ "$new" = true ]
then
	pn "\n\033[33mWARNING:\033[0m Running this with the \033[1m-n\033[0m flag will delete the existing \033[1mcert.der\033[0m file and replace it with one you will be creating."
	pn "This is necessary to build from source. If you'd like to continue, hit enter. Else, cancel execution of this script\n"
	pn "These new certificates will need a password to function correctly, which you'll need to provide."

	pn "Please enter it here: " -n
	read -r pass
	pn "Please enter again for verification: " -n
	read -r passcheck

	while ! [[ "${pass}" == "${passcheck}" ]]
	do
		pn "\n\033[33mWARNING:\033[0m passwords are not equal. Please try again."
		pn "Please enter the password: " -n
		read -r pass
		pn "Please enter again for verification: " -n
		read -r passcheck
	done

	pn "\033[35m==>\033[0m Creating certificate..."
	openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 9999 -nodes -subj "/C=ZZ/ST=./L=./O=./CN=smserver.com"
	openssl x509 -outform der -in cert.pem -out "${ROOTDIR}/src/SMServer/cert.der"
	openssl pkcs12 -export -out "${ROOTDIR}/src/SMServer/identity.pfx" -inkey key.pem -in cert.pem -password pass:"$pass"

	rm key.pem cert.pem

	echo -en "class PKCS12Identity {\n\tstatic let pass: String = \"${pass}\"\n}" > ${ROOTDIR}/src/SMServer/shared/IdentityPass.swift

	olddir="$(pwd)"
	cd "${ROOTDIR}/src" || err "Source directory is gone"
	pn "\033[35m==>\033[0m Installing pods..."
	pod install

	cd "$olddir" || err "$olddir is gone"
	pn "" # for the newline
fi

if [ "$deb" = true ] || [ "$ipa" = true ]
then
	pn "\033[34m==>\033[0m Checking files and LLVM Version..."
	llvm_vers=$(llvm-gcc --version | grep -oE "clang\-[0-9]{4,}" | sed 's/clang\-//g')
	[ "${llvm_vers}" -lt 1200 ] && \
		err "You are using llvm < 1200 (Xcode 11.7 or lower); this will fail to compile. Please install Xcode 12.0 or higher to build SMServer."

	{ ! [ -f ${ROOTDIR}/src/SMServer/identity.pfx ] || ! [ -f ${ROOTDIR}/src/SMServer/shared/IdentityPass.swift ]; } && \
		err "You haven't created some files necessary to compile this. Please run this script with the \033[1m-n\033[0m or \033[1m--new\033[0m flag first"

	if [ "$min" = true ]
	then
		! command -v minify && err "Please install minify to minify asset files"

		pn "\033[34m==>\033[0m Minifying css & html files..."
		cp -r "${html_dir}/" "${html_tmp}/"

		find "$html_tmp" -name "*.css" | while read -r file
		do
			newfile="${file//$(printf "%q" "$html_tmp")/$(printf "%q" "$html_dir")}"
			minify "$file" > "$newfile"
		done

		find "$html_tmp" -name "*.html" | while read -r file
		do
			newfile="${file//$(printf "%q" "$html_tmp")/$(printf "%q" "$html_dir")}"
			minify --html-keep-comments --html-keep-document-tags --html-keep-end-tags --html-keep-quotes --html-keep-whitespace "$file" > "$newfile"
		done
	fi

	rm -rf "${ROOTDIR}/package/SMServer.xcarchive"
	pn "\033[34m==>\033[0m Cleaning and archiving package..."
	xcodebuild clean archive -workspace "${ROOTDIR}/src/SMServer.xcworkspace" -scheme SMServer -archivePath "${ROOTDIR}/package/SMServer.xcarchive" -destination generic/platform=iOS -allowProvisioningUpdates \
		|| err "Failed to archive package. Run again with \033[1m-v\033[0m to see why"

	pn "\033[34m==>\033[0m Codesigning..."
	codesign --entitlements "${ROOTDIR}/src/app.entitlements" -f --deep -s "${DEV_CERT}" "${ROOTDIR}/package/SMServer.xcarchive/Products/Applications/SMServer.app"

	pn "✅ \033[1mSMServer.app successfully created\033[0m\n"
fi

if [ "$deb" = true ]
then
	recv=false

	pn "\033[92m==>\033[0m Extracting \033[1mSMServer.app\033[0m..."
	mkdir -p "${ROOTDIR}/package/deb/Applications"
	rm -rf "${ROOTDIR}/package/deb/Applications/SMServer.app"
	cp -r "${ROOTDIR}/package/SMServer.xcarchive/Products/Applications/SMServer.app" "${ROOTDIR}/package/deb/Applications/SMServer.app"

	pn "\033[92m==>\033[0m Building \033[1mlibsmserver\033[0m..."
	cd "${ROOTDIR}/libsmserver" || err "The libsmserver directory is gone."

	make -B package FINALPACKAGE=1 || err "Failed to build libsmserver. Run with the \033[1m-v\033[0m to see details"
	cd ".." || err "The parent directory is gone."

	cp "${ROOTDIR}/libsmserver/lib/libsmserver.dylib" "${ROOTDIR}/package/deb/Library/MobileSubstrate/DynamicLibraries/"
	cp "${ROOTDIR}/libsmserver/libsmserver.plist" "${ROOTDIR}/package/deb/Library/MobileSubstrate/DynamicLibraries/"

	pn "\033[92m==>\033[0m Building \033[1m.deb\033[0m..."
	dpkg -b "${ROOTDIR}/package/deb"
	{ mv "${ROOTDIR}/package/deb.deb" "${ROOTDIR}/package/SMServer_${vers}.deb" && recv=true; } || \
		pn "\033[33;1mWARNING:\033[0m Failed to create .deb. Run with \033[1m-v\033[0m to see more details."

	if [ "$recv" = true ]
	then
		pn "✅ SMServer_${vers}.deb successfully created at \033[1m${ROOTDIR}/package/SMServer_${vers}.deb\033[0m\n"
	else
		rm "${ROOTDIR}/package/SMServer_${vers}.deb" # Since it may be corrupted
	fi
fi

if [ "$ipa" = true ]
then
	pn "\033[35m==>\033[0m Extracting \033[1mSMServer.app\033[0m..."
	mkdir -p "${ROOTDIR}/package/Payload"
	rm -r "${ROOTDIR}/package/Payload/SMServer.app"
	cp -r "${ROOTDIR}/package/SMServer.xcarchive/Products/Applications/SMServer.app" "${ROOTDIR}/package/Payload/SMServer.app"

	pn "\033[35m==>\033[0m Compressing payload into \033[1mSMServer_${vers}.ipa\033[0m..."
	ditto -c -k --sequesterRsrc --keepParent "${ROOTDIR}/package/Payload" "${ROOTDIR}/package/SMServer_${vers}.ipa"

	pn "✅ SMServer_${vers}.ipa successfully created a† \033[1m${ROOTDIR}/package/SMServer_${vers}.ipa\033[0m"
fi

leave
