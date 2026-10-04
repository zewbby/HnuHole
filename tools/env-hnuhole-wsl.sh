# Source this file from a WSL Bash session.
# HNUHOLE_ENV_ROOT may override the installed D-drive environment root.
export HNUHOLE_ENV_ROOT="${HNUHOLE_ENV_ROOT:-/mnt/d/zewbbyTest/Hnuhole-env}"
export FLUTTER_ROOT="$HNUHOLE_ENV_ROOT/linux/flutter"
export JAVA_HOME="$HNUHOLE_ENV_ROOT/linux/jdk-17.0.20.1+1"
export ANDROID_HOME="$HNUHOLE_ENV_ROOT/linux/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$HNUHOLE_ENV_ROOT/android-user-linux"
export ANDROID_AVD_HOME="$HNUHOLE_ENV_ROOT/avd-linux"
export PUB_CACHE="$HNUHOLE_ENV_ROOT/pub-cache-linux"
export GRADLE_USER_HOME="$HNUHOLE_ENV_ROOT/gradle-cache"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export AUTHLAB_MOBILE_FLUTTER="$FLUTTER_ROOT/bin/flutter"
export GOPATH="$HNUHOLE_ENV_ROOT/go-modules-linux"
export GOCACHE="$HNUHOLE_ENV_ROOT/go-build-linux"
export GOBIN="$HNUHOLE_ENV_ROOT/linux/bin"
export OAPI_CODEGEN="$GOBIN/oapi-codegen"
export GOPROXY=https://goproxy.cn,direct
export PYTHONPATH="$HNUHOLE_ENV_ROOT/linux/python-validation${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$GOBIN:$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:$PATH"

for hnuhole_required in "$FLUTTER_ROOT" "$JAVA_HOME" "$ANDROID_HOME"; do
    if [ ! -d "$hnuhole_required" ]; then
        printf 'Tool installation missing: %s\n' "$hnuhole_required" >&2
        return 1
    fi
done
unset hnuhole_required
