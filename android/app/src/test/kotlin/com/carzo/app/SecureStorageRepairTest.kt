package com.carzo.app

import android.content.SharedPreferences
import com.carzo.app.SecureStorageRepair.KEYSET_KEY
import com.carzo.app.SecureStorageRepair.KEYSET_VALUE
import com.carzo.app.SecureStorageRepair.LEGACY_ALGORITHM_PREFIX
import com.carzo.app.SecureStorageRepair.LEGACY_KEY_PREFIX
import com.carzo.app.SecureStorageRepair.Outcome
import java.io.CharConversionException
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStoreException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM tests for the decision logic (no Keystore, no device). The real
 * Keystore/Tink behaviour is covered by the emulator scenarios documented in
 * the PR; here we pin down WHAT is removed and WHEN.
 */
class SecureStorageRepairTest {

    /** Minimal in-memory SharedPreferences; records misuse (clear()). */
    private class FakePrefs(initial: Map<String, String> = emptyMap()) : SharedPreferences {
        val data = LinkedHashMap<String, Any?>(initial)
        var clearCalled = false
        var commitResult = true

        override fun getAll(): MutableMap<String, *> = LinkedHashMap(data)
        override fun getString(key: String, defValue: String?): String? =
            if (data.containsKey(key)) data[key] as String? else defValue
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String, defValue: Int) = defValue
        override fun getLong(key: String, defValue: Long) = defValue
        override fun getFloat(key: String, defValue: Float) = defValue
        override fun getBoolean(key: String, defValue: Boolean) = defValue
        override fun contains(key: String) = data.containsKey(key)
        override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}

        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            private val removals = mutableListOf<String>()
            private var clear = false
            override fun putString(key: String, value: String?) = this
            override fun putStringSet(key: String, values: MutableSet<String>?) = this
            override fun putInt(key: String, value: Int) = this
            override fun putLong(key: String, value: Long) = this
            override fun putFloat(key: String, value: Float) = this
            override fun putBoolean(key: String, value: Boolean) = this
            override fun remove(key: String): SharedPreferences.Editor { removals += key; return this }
            override fun clear(): SharedPreferences.Editor { clear = true; return this }
            override fun commit(): Boolean {
                if (!commitResult) return false
                if (clear) { clearCalled = true; data.clear() }
                removals.forEach { data.remove(it) }
                return true
            }
            override fun apply() { commit() }
        }
    }

    private val opaqueEntryA = "ARfZfrNvo/2iej6JCdXZxI2B1QBHoQCWpY1fuOzEgW"
    private val opaqueEntryB = "ARfZfrPpOFjXq9ioQqUfkpRcsuMARBA3FxqnGXZafGZZ"
    private val legacyToken = "${LEGACY_KEY_PREFIX}_auth_token"
    private val legacyRefresh = "${LEGACY_KEY_PREFIX}_auth_refresh_token"

    private fun staleSession() = FakePrefs(
        linkedMapOf(
            KEYSET_KEY to "k", KEYSET_VALUE to "v",
            opaqueEntryA to "x", opaqueEntryB to "y",
            legacyToken to "legacy-a", legacyRefresh to "legacy-r",
            "${LEGACY_ALGORITHM_PREFIX}Key" to "RSA_ECB_PKCS1Padding",
            "${LEGACY_ALGORITHM_PREFIX}Storage" to "AES_CBC_PKCS7Padding",
        ),
    )

    @Test
    fun freshInstallWithoutKeysetsIsNotTouchedAndNotProbed() {
        val prefs = FakePrefs()
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) { probes++ }
        assertEquals(Outcome.NOT_NEEDED, outcome)
        assertEquals(0, probes)
        assertTrue(prefs.data.isEmpty())
    }

    @Test
    fun healthyStorageIsLeftExactlyAsIs() {
        val prefs = FakePrefs(linkedMapOf(KEYSET_KEY to "k", KEYSET_VALUE to "v", opaqueEntryA to "x"))
        val before = LinkedHashMap(prefs.data)
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) { probes++ }
        assertEquals(Outcome.HEALTHY, outcome)
        assertEquals(1, probes)
        assertEquals(before, prefs.data)
    }

    @Test
    fun aeadFailureDropsOnlyDeadEncryptedStateAndKeepsLegacySession() {
        val prefs = staleSession()
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) {
            probes++
            // The first two probes fail like the real keyset unwrap (the second
            // confirms the failure is repeatable); the third (after cleanup)
            // succeeds, like Tink creating a fresh keyset.
            if (probes <= 2) throw AEADBadTagException()
        }
        assertEquals(Outcome.REPAIRED, outcome)
        assertEquals(3, probes)

        // Dead state is gone ...
        assertFalse(prefs.contains(KEYSET_KEY))
        assertFalse(prefs.contains(KEYSET_VALUE))
        assertFalse(prefs.contains(opaqueEntryA))
        assertFalse(prefs.contains(opaqueEntryB))
        // ... everything still readable by the plugin's migration is kept.
        assertTrue(prefs.contains(legacyToken))
        assertTrue(prefs.contains(legacyRefresh))
        assertTrue(prefs.contains("${LEGACY_ALGORITHM_PREFIX}Key"))
        assertTrue(prefs.contains("${LEGACY_ALGORITHM_PREFIX}Storage"))
        assertEquals("legacy-a", prefs.getString(legacyToken, null))
        // Never a blanket reset (resetOnError / deleteAll equivalent).
        assertFalse(prefs.clearCalled)
    }

    @Test
    fun aOneOffAeadGlitchThatRecoversNeverDeletesAnything() {
        val prefs = staleSession()
        val before = LinkedHashMap(prefs.data)
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) { if (++probes == 1) throw AEADBadTagException() }
        assertEquals(Outcome.HEALTHY, outcome)
        assertEquals(2, probes)
        assertEquals(before, prefs.data)
    }

    @Test
    fun aeadThatTurnsIntoADifferentErrorOnRetryNeverDeletesAnything() {
        val prefs = staleSession()
        val before = LinkedHashMap(prefs.data)
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) {
            if (++probes == 1) throw AEADBadTagException() else throw KeyStoreException("busy")
        }
        assertEquals(Outcome.LEFT_UNTOUCHED, outcome)
        assertEquals(2, probes)
        assertEquals(before, prefs.data)
    }

    @Test
    fun aeadFailureWrappedInCauseChainIsRecognised() {
        val wrapped = GeneralSecurityException("outer", IOException("mid", AEADBadTagException()))
        assertTrue(SecureStorageRepair.isUndecryptableKeyset(wrapped))
    }

    @Test
    fun unparseableKeysetIsTreatedAsPermanent() {
        // Real message produced by Tink's SharedPrefKeysetReader on a garbled value.
        val garbled = CharConversionException(
            "can't read keyset; the pref value $KEYSET_VALUE is not a valid hex string",
        )
        assertTrue(SecureStorageRepair.isUndecryptableKeyset(garbled))

        val prefs = staleSession()
        var probes = 0
        val outcome = SecureStorageRepair.repair(prefs) { if (++probes <= 2) throw garbled }
        assertEquals(Outcome.REPAIRED, outcome)
        assertTrue(prefs.contains(legacyToken))
        assertFalse(prefs.contains(KEYSET_VALUE))
    }

    @Test
    fun unrelatedCharConversionFailureIsNotPermanent() {
        assertFalse(SecureStorageRepair.isUndecryptableKeyset(CharConversionException("something else")))
    }

    @Test
    fun nonPermanentFailuresNeverDiscardAnything() {
        val failures = listOf<Throwable>(
            IOException("disk"),
            GeneralSecurityException("generic"),
            KeyStoreException("keystore unavailable"),
            IllegalStateException("boom"),
            RuntimeException("device locked"),
        )
        for (failure in failures) {
            val prefs = staleSession()
            val before = LinkedHashMap(prefs.data)
            val outcome = SecureStorageRepair.repair(prefs) { throw failure }
            assertEquals("for $failure", Outcome.LEFT_UNTOUCHED, outcome)
            assertEquals("for $failure", before, prefs.data)
        }
    }

    @Test
    fun failedCommitLeavesEverythingInPlace() {
        val prefs = staleSession().also { it.commitResult = false }
        val before = LinkedHashMap(prefs.data)
        val outcome = SecureStorageRepair.repair(prefs) { throw AEADBadTagException() }
        assertEquals(Outcome.LEFT_UNTOUCHED, outcome)
        assertEquals(before, prefs.data)
    }

    @Test
    fun stillFailingAfterCleanupIsReportedButKeepsLegacyData() {
        val prefs = staleSession()
        val outcome = SecureStorageRepair.repair(prefs) { throw AEADBadTagException() }
        assertEquals(Outcome.LEFT_UNTOUCHED, outcome)
        assertTrue(prefs.contains(legacyToken))
        assertFalse(prefs.clearCalled)
    }

    @Test
    fun repairIsIdempotentOnceCleaned() {
        val prefs = staleSession()
        var probes = 0
        SecureStorageRepair.repair(prefs) { if (++probes <= 2) throw AEADBadTagException() }
        // After a successful repair the plugin writes a new keyset; simulate it.
        prefs.data[KEYSET_KEY] = "new-k"
        prefs.data[KEYSET_VALUE] = "new-v"
        val outcome = SecureStorageRepair.repair(prefs) { /* healthy now */ }
        assertEquals(Outcome.HEALTHY, outcome)
        assertTrue(prefs.contains(legacyToken))
    }

    @Test
    fun deadEntryClassification() {
        assertTrue(SecureStorageRepair.isDeadEncryptedEntry(KEYSET_KEY))
        assertTrue(SecureStorageRepair.isDeadEncryptedEntry(KEYSET_VALUE))
        assertTrue(SecureStorageRepair.isDeadEncryptedEntry(opaqueEntryA))
        assertFalse(SecureStorageRepair.isDeadEncryptedEntry(legacyToken))
        assertFalse(SecureStorageRepair.isDeadEncryptedEntry("${LEGACY_ALGORITHM_PREFIX}Key"))
    }
}
