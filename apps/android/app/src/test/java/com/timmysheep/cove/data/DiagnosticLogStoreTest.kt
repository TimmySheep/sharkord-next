package com.timmysheep.cove.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DiagnosticLogStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun redactsCredentialsFromDiagnosticEntries() {
        val store = DiagnosticLogStore(temporaryFolder.newFolder())
        val sanitized = store.sanitize(
            "token=secret-value password: secret-password " +
                "Bearer abc.def.ghi Authorization: Bearer header-secret " +
                "https://example.test/?accessToken=query-secret"
        )

        assertFalse(sanitized.contains("secret-value"))
        assertFalse(sanitized.contains("secret-password"))
        assertFalse(sanitized.contains("abc.def.ghi"))
        assertFalse(sanitized.contains("header-secret"))
        assertFalse(sanitized.contains("query-secret"))
        assertTrue(sanitized.contains("[REDACTED]"))
    }

    @Test
    fun rotatesAndExportsTheRecentLogFiles() {
        val store = DiagnosticLogStore(temporaryFolder.newFolder(), maximumFileBytes = 80)
        store.append("INFO", "test", "first entry")
        store.append("ERROR", "test", "second entry")

        val exported = store.exportText()

        assertTrue(exported.contains("first entry"))
        assertTrue(exported.contains("second entry"))
    }
}
