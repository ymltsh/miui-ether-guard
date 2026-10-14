# Build helper.jar

Requires JDK 17+ and Google R8 8.3.37.

Official artifact: https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar

SHA256: 900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199

From the repository root, using a POSIX shell:

```sh
mkdir -p build/classes
javac --release 8 -d build/classes module/src/EtherGuard.java
java -cp build/r8.jar com.android.tools.r8.D8 --min-api 30 --output module/helper.jar build/classes/local/etherguard/*.class
```

Place the downloaded R8 jar at build/r8.jar and verify its checksum before using it.

Package the contents of module/ at the ZIP root, with LF line endings. module.prop must be at the ZIP root. Preserve executable permissions for shell scripts; the Magisk customize script also sets them during installation. The binary helper.jar is included for direct use. No SDK android.jar is required because the helper resolves Android APIs at runtime.
