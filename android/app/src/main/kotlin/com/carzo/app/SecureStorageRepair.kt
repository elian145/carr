package com.carzo.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.io.CharConversionException
import java.security.GeneralSecurityException
import javax.crypto.AEADBadTagException

/**
 * Heals the one permanent failure mode of `flutter_secure_storage`'s
 * `EncryptedSharedPreferences` backend on Android:
 *
 *   javax.crypto.AEADBadTagException  (Keystore `VERIFICATION_FAILED`)
 *
 * Cause
 * -----
 * `shared_prefs/FlutterSecureStorage.xml` stores Tink keysets that are wrapped
 * by an AES-GCM master key in the Android Keystore (alias
 * `_androidx_security_master_key_`). The prefs file travels with Android Auto
 * Backup / device transfer / `adb restore`, the Keystore key never does. When
 * the file lands next to a different (or freshly generated) master key, the
 * keysets can no longer be unwrapped. The plugin then logs
 * `EncryptedSharedPreferences initialization failed` on every start and
 * silently drops to its legacy cipher for the rest of the process.
 *
 * What the data looks like at that point
 * --------------------------------------
 *  - the two Tink keysets: unwrappable by nothing, ever;
 *  - the entries encrypted with them (opaque key names): unreadable, ever;
 *  - entries the plugin wrote in its legacy format while in fallback mode
 *    (key names carry [LEGACY_KEY_PREFIX]) plus the legacy algorithm markers:
 *    perfectly readable, and exactly what the plugin's own
 *    `checkAndMigrateToEncrypted` moves back into encrypted storage once
 *    encrypted initialisation succeeds again. This is how an already signed-in
 *    install keeps its session.
 *
 * Fix
 * ---
 * Before the Flutter engine (and therefore the plugin) can touch the file, probe
 * encrypted initialisation exactly like the plugin does. Only if that fails
 * with an `AEADBadTagException` (or an unparseable keyset) -- i.e. the keysets
 * are provably undecryptable with the *current* master key, and the identical
 * failure repeats on an immediate second probe -- remove the dead keysets and
 * the dead encrypted entries. Everything else is left strictly alone:
 *  - the Keystore master key is never deleted or replaced;
 *  - legacy-format entries and algorithm markers are kept (session survives);
 *  - any other error (Keystore temporarily unavailable, device locked, ...) is
 *    treated as transient and changes nothing, so no data is ever discarded on a
 *    guess;
 *  - nothing here enables the plugin's `resetOnError` / `deleteAll()`.
 *
 * Secret values are never read, logged or copied; logs carry counts and
 * exception class names only.
 */
internal object SecureStorageRepair {
    private const val TAG = "CarNetSecureStore"

    /** Matches `FlutterSecureStorage.SHARED_PREFERENCES_NAME` in the plugin. */
    internal const val PREFS_NAME = "FlutterSecureStorage"

    /** Tink keyset entries EncryptedSharedPreferences keeps in the same file. */
    internal const val KEYSET_KEY = "__androidx_security_crypto_encrypted_prefs_key_keyset__"
    internal const val KEYSET_VALUE = "__androidx_security_crypto_encrypted_prefs_value_keyset__"

    /** `FlutterSecureStorage.ELEMENT_PREFERENCES_KEY_PREFIX` (plugin default). */
    internal const val LEGACY_KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"

    /** `StorageCipherFactory.ELEMENT_PREFERENCES_ALGORITHM_PREFIX`. */
    internal const val LEGACY_ALGORITHM_PREFIX = "FlutterSecureSAlgorithm"

    internal enum class Outcome {
        /** No encrypted keysets yet (fresh install or never used): nothing to do. */
        NOT_NEEDED,

        /** Encrypted storage opens fine with the current Keystore key. */
        HEALTHY,

        /** Dead keysets/entries were discarded; a fresh keyset can now be created. */
        REPAIRED,

        /** Probe failed for a reason that is not provably permanent; nothing changed. */
        LEFT_UNTOUCHED,
    }

    /** Production entry point. Never throws. */
    fun run(context: Context): Outcome {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return Outcome.NOT_NEEDED
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            repair(prefs) { openEncryptedPrefs(context) }
        } catch (t: Throwable) {
            Log.w(TAG, "Secure storage pre-flight check skipped (${t.javaClass.simpleName})")
            Outcome.LEFT_UNTOUCHED
        }
    }

    /**
     * Pure decision logic, separated from Android/Keystore so it is unit-testable.
     *
     * @param probe must perform the same initialisation the plugin performs and
     *        throw if it fails.
     */
    internal fun repair(prefs: SharedPreferences, probe: () -> Unit): Outcome {
        if (!prefs.contains(KEYSET_KEY) && !prefs.contains(KEYSET_VALUE)) {
            return Outcome.NOT_NEEDED
        }

        try {
            probe()
            return Outcome.HEALTHY
        } catch (t: Throwable) {
            if (!isUndecryptableKeyset(t)) {
                Log.w(
                    TAG,
                    "Encrypted storage probe failed (${rootName(t)}); not treated as " +
                        "permanent, leaving stored data untouched",
                )
                return Outcome.LEFT_UNTOUCHED
            }
        }

        // Never delete on a single observation: a permanent failure must repeat
        // identically. A one-off glitch (or a different error on retry) leaves
        // everything untouched; the plugin's existing fallback still applies.
        try {
            probe()
            Log.w(TAG, "Encrypted storage probe failed once but recovered; nothing changed")
            return Outcome.HEALTHY
        } catch (t: Throwable) {
            if (!isUndecryptableKeyset(t)) {
                Log.w(
                    TAG,
                    "Encrypted storage probe failure was not repeatable (${rootName(t)}); " +
                        "leaving stored data untouched",
                )
                return Outcome.LEFT_UNTOUCHED
            }
        }

        val dead = prefs.all.keys.filter(::isDeadEncryptedEntry)
        val kept = prefs.all.size - dead.size
        val editor = prefs.edit()
        dead.forEach { editor.remove(it) }
        // commit(), not apply(): the plugin may open this file right after us.
        if (!editor.commit()) {
            Log.w(TAG, "Could not persist secure storage repair; leaving as is")
            return Outcome.LEFT_UNTOUCHED
        }

        Log.w(
            TAG,
            "Discarded ${dead.size} undecryptable secure storage entries " +
                "(stale Keystore key, typically after backup restore); kept $kept legacy entries",
        )

        // Confirm the freshly cleaned file now initialises (this creates the new keyset).
        return try {
            probe()
            Outcome.REPAIRED
        } catch (t: Throwable) {
            Log.w(TAG, "Encrypted storage still unavailable after cleanup (${rootName(t)})")
            Outcome.LEFT_UNTOUCHED
        }
    }

    /**
     * True only when the stored keysets are provably unusable, which no retry
     * can change:
     *  - Keystore reports a GCM tag verification failure while unwrapping them
     *    ([AEADBadTagException]): wrong/new master key, or flipped bits;
     *  - Tink cannot even parse the stored keyset ([CharConversionException]
     *    "can't read keyset ... not a valid hex string"): truncated/garbled file.
     * Both are deterministic functions of bytes already on disk. Anything else
     * (Keystore busy/unavailable, I/O errors, ...) may be transient and is not
     * matched.
     */
    internal fun isUndecryptableKeyset(t: Throwable): Boolean {
        var cur: Throwable? = t
        var depth = 0
        while (cur != null && depth < 10) {
            if (cur is AEADBadTagException) return true
            if (cur is CharConversionException && cur.message?.contains("keyset") == true) return true
            cur = cur.cause
            depth++
        }
        return false
    }

    /**
     * Entries that can only have been produced by (now unusable) encrypted
     * storage: the keysets themselves, and every entry that is neither a
     * legacy-format value nor a legacy algorithm marker.
     */
    internal fun isDeadEncryptedEntry(key: String): Boolean {
        if (key == KEYSET_KEY || key == KEYSET_VALUE) return true
        if (key.startsWith(LEGACY_KEY_PREFIX)) return false
        if (key.startsWith(LEGACY_ALGORITHM_PREFIX)) return false
        return true
    }

    private fun rootName(t: Throwable): String {
        var cur: Throwable = t
        var depth = 0
        while (cur.cause != null && depth < 10) {
            cur = cur.cause!!
            depth++
        }
        return cur.javaClass.simpleName
    }

    /** Mirrors `FlutterSecureStorage.initializeEncryptedSharedPreferencesManager`. */
    @Throws(GeneralSecurityException::class, java.io.IOException::class)
    private fun openEncryptedPrefs(context: Context) {
        val masterKey = MasterKey.Builder(context)
            .setKeyGenParameterSpec(
                KeyGenParameterSpec.Builder(
                    MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setKeySize(256)
                    .build(),
            )
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }
}
