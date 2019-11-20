/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

package mozilla.telemetry.glean.testing

import androidx.annotation.VisibleForTesting
import mozilla.telemetry.glean.Glean
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/**
 * This implements a JUnit rule for writing tests for Glean SDK metrics.
 *
 * The rule takes care of sending Glean SDK pings to a local server, at the
 * address: "http://localhost:<port>".
 *
 * This is useful for Android instrumented tests, where we don't want to
 * initialize Glean more than once but still want to send pings to a local
 * server for validation.
 *
 * Example usage:
 *
 * ```
 * // Add the following lines to you test class.
 * @get:Rule
 * val gleanRule = GleanTestLocalServer(3785)
 * ```
 *
 * @param localPort the port of the local ping server
 */
@VisibleForTesting(otherwise = VisibleForTesting.NONE)
class GleanTestLocalServer(
    private val localPort: Int
) : TestWatcher() {
    /**
     * Invoked when a test is about to start.
     */
    override fun starting(description: Description?) {
        Glean.testSetLocalEndpoint(localPort)
    }
}
