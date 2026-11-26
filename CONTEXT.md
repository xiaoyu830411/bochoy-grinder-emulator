# Bochoy Grinder Emulator

A simulator of the CRYSTAL grinder at the Decaid plugin's real BLE GATT boundary, intended for interactive integration testing and repeatable automated tests.

## Language

**Bochoy Grinder Emulator**:
A real BLE GATT peripheral that stands in for the CRYSTAL grinder when testing the Decaid `com.crystal.grinder` plugin. It does not simulate the plugin's GATT host or the Decaid HTTP/WebSocket API.
_Avoid_: Fake host, HTTP simulator, grinder app

**Protocol Guarantee**:
Observable behavior explicitly defined by the CRYSTAL BLE protocol documentation. A simulator must not present anything weaker or stronger as guaranteed by the real device.

**Simulation Assumption**:
A deliberate, documented behavior chosen where the protocol and available firmware records do not define the real grinder's behavior. It is test input, not a claim about physical hardware or firmware.
_Avoid_: Protocol requirement, real-device behavior

**Deterministic Device Model**:
The simulator's explicit model of grinder state and observable transitions, combining Protocol Guarantees with clearly separated Simulation Assumptions.
_Avoid_: Mechanical simulation, high-fidelity firmware emulation

**System State**:
The grinder's protocol-visible idle or device-active state. Only `0` means idle and `1` means device active — a motor Run or an Apply Operation in progress; every other value is unknown, never a safe-idle indication.
_Avoid_: Connected state, motor-stopped proof

**Current Grind Setting**:
The value exposed through `SERVO_ANGLE`. It is distinct from the target and is not proof that a physical mechanism has reached its position.
_Avoid_: Target setting, applied mechanical position

**Target Grind Setting**:
The value held by `TF_ANGLE` and captured by an Apply Operation. Writing it alone does not change the Current Grind Setting.
_Avoid_: Current setting

**Motor Setting**:
The register value exposed through `MT_RPM`. It is not assumed to be a measured burr speed or a value in physical rpm units.
_Avoid_: Measured RPM, motor speed

**Feed Setting**:
The register value exposed through `XD_RPM`, whose mechanical meaning and physical unit remain unspecified.
_Avoid_: Feed RPM, feed rate, dose

**Device Identity**:
The advertised `CRYSTAL-` name and primary GATT service used to discover the simulated grinder. The display name is not authentication or proof of a physical device's identity.

**Power-on State**:
The explicit initial register values of a new simulation, either the simulator defaults or values supplied by a Scenario. The default `SERVO_ANGLE=830` is a vendor-confirmed real-device power-on value; the remaining default zeros are simulator defaults consistent with the observed idle device.
_Avoid_: Firmware boot image

**Device Power**:
The simulator-only on/off lifecycle of the virtual grinder, distinct from both System State and simulator process lifetime. Power-off stops advertising, requests disconnection of Observed Centrals, ends the active Run and pending Apply Operation, and disables device controls until power-on. Power-on starts idle, always resumes advertising as a fresh device start, resets the volatile Motor, Feed, Target Grind, and Boot Command registers to zero, and retains only the Current Grind Setting. These transitions are Simulation Assumptions, not claims about physical grinder power or safety behavior.
_Avoid_: System State, Power-on State, simulator process exit

**Run Mode**:
The simulator's manual, timed, or smart interpretation of the corresponding start command. Run Modes define deterministic endings for a simulated run without claiming to reproduce the real grinder's internal triggers or timing.
_Avoid_: Grind recipe, extraction mode

**Link Loss**:
The actual end of a BLE connection between a central and the simulated grinder. It is distinct from unsubscribing, ending a test session, or stopping a simulation, and does not by itself prove any subsequent device behavior.
_Avoid_: Unsubscription, session-end command

**Observed Central**:
A central that has become visible through GATT activity such as a subscription, read, or write. Its central identifier and local alias are observations, not proof of a complete list of currently connected physical devices. One central may have multiple Observation Records over time.
_Avoid_: Named connected phone, confirmed live connection inventory

**Observation Record**:
One episode of activity attributed to an Observed Central, with its own record identity distinct from the central identifier. Subsequent activity joins the current record until a Manually Confirmed Disconnection; later activity from the same central then starts a new record. Unsubscription, Observed Session End, and Disconnect Requests do not themselves end a record.
_Avoid_: BLE connection callback, guaranteed link lifetime

**Manually Confirmed Disconnection**:
A user's explicit statement, based on the phone or tablet, that the episode represented by an Observation Record has ended. It is a user-supplied observation rather than a CoreBluetooth Link Loss callback. Only such a record may become a Hidden Observation.
_Avoid_: Automatically detected Link Loss, Disconnect Request

**Hidden Observation**:
An Observation Record omitted from the ordinary shared device-activity view after a Manually Confirmed Disconnection. Hiding and restoring affect every monitoring view, preserve the central identity, local alias, raw events, and persistent log, and do not operate on the BLE link. Hidden records remain restorable individually or together.
_Avoid_: Event deletion, central disconnection, browser-only filtering

**Disconnect Request**:
A simulator-initiated attempt to end existing BLE links as part of Device Power-off. It remains unconfirmed until supported by observable evidence and must not be equated with a successful Link Loss merely because the request was issued.
_Avoid_: Confirmed central disconnection, Observed Session End

**Observed Session End**:
A simulator-observed or explicitly triggered end of a testing session that activates the Disconnect Policy. It may be inferred from lost subscriptions without claiming that a Link Loss was reliably detected.
_Avoid_: Confirmed link loss, central disconnection callback

**Disconnect Policy**:
The Scenario-selected behavior of the Deterministic Device Model after an Observed Session End: pause, continue, or stop. The default is pause; none of these policies is evidence of a real grinder's fail-safe behavior.
_Avoid_: Watchdog behavior, emergency stop

**Boot Command Register**:
The simulator's readable record of the last defined start, stop, or apply command. It defaults to `0`, is not replaced by reserved command values, and never represents completion of the requested action; its notifications are not part of the simulator's normal behavior.
_Avoid_: Action acknowledgement, execution status

**Apply Operation**:
A deterministic request to make the Current Grind Setting equal to the Target Grind Setting captured when the apply command arrives. A delayed Apply Operation is superseded only by a newer Apply Operation, a Test Override, or a Scenario reset; changing the target alone does not alter the captured value.
_Avoid_: Completed grind adjustment, transactional setting write

**Apply Auto-Idle Timer**:
The simulator rule that an Apply Operation with no active Run marks System State device-active and returns it to idle after a fixed five seconds. It is a Simulation Assumption, not a vendor-confirmed timing, and it never runs during an active Run.
_Avoid_: Real grinder apply duration, mechanical settling time

**Test Override**:
A local testing action that forces a register value or notification outside the normal BLE command rules, including values undefined by the protocol. It is explicitly recorded as test input and never treated as a normal device transition.
_Avoid_: Device write, normal state, protocol command

**Scenario**:
A named, repeatable arrangement of initial device state, Simulation Assumptions, and Fault Injections used during manual or automated testing.
_Avoid_: Recipe, grinder profile

**Fault Injection**:
A deliberate abnormal device or link behavior enabled for a test, such as a delayed response, missing notification, stalled state transition, or unexpected disconnect. Fault Injections are disabled unless a Scenario enables them.
_Avoid_: Default behavior, random failure
