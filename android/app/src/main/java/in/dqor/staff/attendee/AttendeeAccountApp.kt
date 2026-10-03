package `in`.dqor.staff.attendee

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `in`.dqor.staff.experience.AttendeeTheme
import kotlinx.coroutines.launch

@Composable
fun AttendeeAccountApp(controller: AttendeeController, onClose: () -> Unit,
    onAuthorize: (AttendeeAuthorization) -> Unit, onWebsite: () -> Unit, onTickets: () -> Unit,
    browserProblem: String? = null) {
    val state by controller.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    BackHandler { controller.cancel(); onClose() }
    LaunchedEffect(controller) { controller.expire() }
    AttendeeTheme {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                if (controller.isSynthetic) Text("SYNTHETIC LOCAL BRIDGE · no real account, ticket or admission", Modifier.padding(16.dp), style = MaterialTheme.typography.labelLarge)
                LazyColumn(Modifier.widthIn(max = 680.dp).fillMaxWidth().weight(1f).testTag("attendee-account"),
                    contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    item { TextButton(onClick = { controller.cancel(); onClose() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Back to programme") } }
                    item { Text("Your account", style = MaterialTheme.typography.headlineLarge) }
                    item { Text("Pass status is read only. Open the official ticket website for your actual ticket credentials.") }
                    when (val current = state) {
                        AttendeeState.Unavailable -> item {
                            Text("Native account access is not enabled", style = MaterialTheme.typography.titleLarge)
                            Text("Use your account securely in the system browser. Your browser keeps its own sign-in session.")
                        }
                        AttendeeState.SignedOut -> item { SignIn(controller, onAuthorize) }
                        AttendeeState.Authorizing -> item {
                            Text("Continue in your browser", style = MaterialTheme.typography.titleLarge)
                            Text("Return here after verification and consent. If you leave the browser, you can cancel and start again.")
                            TextButton(onClick = controller::cancel, modifier = Modifier.heightIn(min = 48.dp)) { Text("Cancel sign-in") }
                        }
                        AttendeeState.Exchanging -> item {
                            LinearProgressIndicator(Modifier.fillMaxWidth())
                            Text("Completing secure sign-in…", modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                            TextButton(onClick = controller::cancel, modifier = Modifier.heightIn(min = 48.dp)) { Text("Cancel sign-in") }
                        }
                        AttendeeState.Loading -> item {
                            LinearProgressIndicator(Modifier.fillMaxWidth())
                            Text("Checking current account and pass status…", modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                            TextButton(onClick = { scope.launch { controller.logout() } }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Sign out and clear account") }
                        }
                        is AttendeeState.Failed -> item {
                            Text(problemText(current.problem), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                            Text("Private information has been cleared. Sign in again to verify the latest status.")
                            SignIn(controller, onAuthorize)
                        }
                        is AttendeeState.SignedOutResult -> item {
                            Text(when (current.revocation) { AttendeeRevocation.REVOKED -> "Signed out. Server session revoked."; AttendeeRevocation.ALREADY_INVALID -> "Signed out. This session is no longer accepted by the server."; null -> "Account cleared on this device. Server revocation could not be confirmed." }, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                            SignIn(controller, onAuthorize)
                        }
                        is AttendeeState.Ready -> {
                            item {
                                Text(current.snapshot.identity.name ?: "Attendee", style = MaterialTheme.typography.titleLarge)
                                Text(current.snapshot.identity.email)
                                Text("Status checked ${current.snapshot.checkedAt}. Reconnect and refresh before relying on it.", style = MaterialTheme.typography.bodySmall)
                                OutlinedButton(onClick = { scope.launch { controller.refresh() } }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Refresh account status") }
                            }
                            if (current.snapshot.passes.isEmpty()) item {
                                Text("No assigned passes", style = MaterialTheme.typography.titleLarge)
                                Text("Only passes assigned to this verified email appear here. Check purchases and assignments on the website.")
                            }
                            items(current.snapshot.passes, key = { it.id }) { pass ->
                                Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
                                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text(pass.typeName, style = MaterialTheme.typography.titleLarge)
                                        Text(pass.status.name.lowercase().replaceFirstChar { it.titlecase() })
                                        Text("${pass.startsOn ?: "Start date unavailable"} – ${pass.endsOn ?: "End date unavailable"}")
                                        pass.entry.forEach { entry -> Text("${entry.date}: ${if (entry.checkedInAt != null) "entry recorded" else if (entry.eligible) "eligible at last check" else "not eligible at last check"}") }
                                        Text("Status only · no QR or admission action", style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }
                            if (current.snapshot.moreResults && current.snapshot.passes.size < 200) item { TextButton(onClick = { scope.launch { controller.nextPage() } }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Load more pass status") } }
                            if (current.snapshot.moreResults && current.snapshot.passes.size >= 200) item { Text("More pass status is available on the official website.") }
                            item { TextButton(onClick = { scope.launch { controller.logout() } }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Sign out and clear account") } }
                        }
                    }
                    item { OutlinedButton(onClick = onWebsite, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Open account on official website") } }
                    item { TextButton(onClick = onTickets, modifier = Modifier.heightIn(min = 48.dp)) { Text("Open actual tickets on website") } }
                    browserProblem?.let { item { Text(it, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }) } }
                }
            }
        }
    }
}

@Composable private fun SignIn(controller: AttendeeController, authorize: (AttendeeAuthorization) -> Unit) {
    Button(onClick = { controller.begin()?.let(authorize) }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Sign in through system browser") }
}

private fun problemText(problem: AttendeeProblem) = when (problem) {
    AttendeeProblem.EXPIRED -> "Your secure session or sign-in expired."
    AttendeeProblem.REVOKED -> "This account session is no longer valid."
    AttendeeProblem.IDENTITY_CHANGED -> "Account verification changed."
    AttendeeProblem.INVALID_CALLBACK, AttendeeProblem.INVALID_RESPONSE -> "Secure sign-in could not be verified."
    AttendeeProblem.TIMEOUT -> "The request timed out."
    AttendeeProblem.OFFLINE -> "Could not connect to verify account status."
    AttendeeProblem.RATE_LIMITED -> "Too many attempts. Wait three minutes before trying again."
    AttendeeProblem.UNAVAILABLE -> "Native account access is unavailable."
}
