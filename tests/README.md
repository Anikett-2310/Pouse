# Pouse Integration & Protocol Tests

This directory contains integration test scripts and protocol test suites for verifying communication between the Pouse Mobile client and Pouse PC client.

## Test Areas
- **Protocol Deserialization**: Verify JSON event parsing against `protocol/PROTOCOL.md`.
- **End-to-End WebSocket Test**: Mock WebSocket client sending synthetic `MOVE`, `CLICK`, and `KEY_PRESS` events to `pc-client`.
