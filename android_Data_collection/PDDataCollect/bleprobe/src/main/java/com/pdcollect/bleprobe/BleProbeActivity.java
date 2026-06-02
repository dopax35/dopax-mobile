package com.pdcollect.bleprobe;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothStatusCodes;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Log;
import android.widget.TextView;
import java.util.ArrayDeque;
import java.util.Locale;
import java.util.Queue;
import java.util.UUID;

public class BleProbeActivity extends Activity {
    private static final String TAG = "BleProbe";
    private static final UUID BEANIE_SERVICE_UUID = UUID.fromString("12345678-90AB-4CDE-8123-1234567890AB");
    private static final UUID CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final long SCAN_TIMEOUT_MS = 60_000L;
    private static final String TARGET_ADDRESS_SUFFIX = ":D4:82";
    private static final byte[] ENABLE_NOTIFY = new byte[] { 0x01, 0x00 };
    private static final byte[] ENABLE_INDICATE = new byte[] { 0x02, 0x00 };

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Queue<BluetoothGattCharacteristic> readQueue = new ArrayDeque<>();
    private TextView output;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private boolean readInFlight;
    private boolean connected;
    private int scanResultsSeen;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        output = new TextView(this);
        output.setTextIsSelectable(true);
        output.setPadding(24, 24, 24, 24);
        setContentView(output);
        log("BLE direct-read probe starting");

        if (!hasBlePermissions()) {
            requestPermissions(
                new String[] {
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.ACCESS_FINE_LOCATION
                },
                10
            );
            return;
        }
        startScan();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (hasBlePermissions()) {
            startScan();
        } else {
            log("Missing BLE permissions; cannot scan");
        }
    }

    @Override
    protected void onDestroy() {
        stopScan();
        if (gatt != null) {
            try {
                gatt.disconnect();
                gatt.close();
            } catch (SecurityException ignored) {
            }
        }
        super.onDestroy();
    }

    private boolean hasBlePermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
        return checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
    }

    private void startScan() {
        BluetoothManager manager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
        scanner = adapter == null ? null : adapter.getBluetoothLeScanner();
        if (scanner == null) {
            log("No BLE scanner available");
            return;
        }

        ScanSettings settings = new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build();
        try {
            scanner.startScan(null, settings, scanCallback);
        log("Scanning for Beanie-like advertisements for " + (SCAN_TIMEOUT_MS / 1000) + "s; suffix=" + TARGET_ADDRESS_SUFFIX);
            handler.postDelayed(() -> {
                if (!connected) {
                    stopScan();
                    log("Scan timed out without a Beanie candidate");
                }
            }, SCAN_TIMEOUT_MS);
        } catch (SecurityException e) {
            log("Scan failed: missing permission");
        }
    }

    private void stopScan() {
        if (scanner == null) return;
        try {
            scanner.stopScan(scanCallback);
        } catch (Exception ignored) {
        }
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            String name = displayName(result);
            boolean hasService = hasBeanieService(result);
            boolean likelyName = isLikelyBeanieName(name);
            BluetoothDevice device = result.getDevice();
            String address = device.getAddress();
            boolean likelyAddress = address != null && address.toUpperCase(Locale.US).endsWith(TARGET_ADDRESS_SUFFIX);
            scanResultsSeen++;
            if (scanResultsSeen <= 250 || likelyName || hasService || likelyAddress || scanResultsSeen % 50 == 0) {
                log("Scan hit " + address + " name=" + name + " service=" + hasService + " rssi=" + result.getRssi());
            }
            if (!hasService && !likelyName && !likelyAddress) return;

            log("Candidate " + address + " name=" + name + " service=" + hasService + " suffix=" + likelyAddress + " rssi=" + result.getRssi());
            stopScan();
            connected = true;
            try {
                gatt = device.connectGatt(BleProbeActivity.this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            } catch (SecurityException e) {
                log("connectGatt failed: missing permission");
            }
        }

        @Override
        public void onScanFailed(int errorCode) {
            log("Scan failed error=" + errorCode);
        }
    };

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            log("GATT state status=" + status + " newState=" + newState + " address=" + safeAddress(gatt));
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    gatt.discoverServices();
                } catch (SecurityException e) {
                    log("discoverServices failed: missing permission");
                }
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            log("Services discovered status=" + status + " count=" + gatt.getServices().size());
            for (BluetoothGattService service : gatt.getServices()) {
                log("Service " + service.getUuid());
                for (BluetoothGattCharacteristic ch : service.getCharacteristics()) {
                    log("  Char " + ch.getUuid() + " props=" + props(ch.getProperties()) + " cccd=" + (ch.getDescriptor(CCCD_UUID) != null));
                    if ((ch.getProperties() & BluetoothGattCharacteristic.PROPERTY_READ) != 0) {
                        readQueue.add(ch);
                    }
                }
            }

            log("Queued direct reads: " + readQueue.size());
            readNext(gatt);
            subscribeBeaniePushCharacteristics(gatt);
        }

        @Override
        public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            byte[] value = characteristic.getValue();
            handleReadResult(gatt, characteristic, value, status);
        }

        @Override
        public void onCharacteristicRead(
            BluetoothGatt gatt,
            BluetoothGattCharacteristic characteristic,
            byte[] value,
            int status
        ) {
            handleReadResult(gatt, characteristic, value, status);
        }

        @Override
        public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
            log("Descriptor write " + descriptor.getCharacteristic().getUuid() + " status=" + status);
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
            handleIncoming("PUSH", characteristic, characteristic.getValue());
        }

        @Override
        public void onCharacteristicChanged(
            BluetoothGatt gatt,
            BluetoothGattCharacteristic characteristic,
            byte[] value
        ) {
            handleIncoming("PUSH", characteristic, value);
        }
    };

    private void handleReadResult(
        BluetoothGatt gatt,
        BluetoothGattCharacteristic characteristic,
        byte[] value,
        int status
    ) {
        readInFlight = false;
        log("READ " + characteristic.getUuid() + " status=" + status + " bytes=" + (value == null ? 0 : value.length) + " hex=" + hex(value));
        if (status == BluetoothGatt.GATT_SUCCESS) {
            handleIncoming("DIRECT_READ", characteristic, value);
        }
        readNext(gatt);
    }

    private void readNext(BluetoothGatt gatt) {
        if (readInFlight) return;
        BluetoothGattCharacteristic next = readQueue.poll();
        if (next == null) {
            log("Direct read queue complete");
            return;
        }
        readInFlight = true;
        try {
            boolean started = gatt.readCharacteristic(next);
            log("Direct read start " + next.getUuid() + " started=" + started);
            if (!started) {
                readInFlight = false;
                handler.postDelayed(() -> readNext(gatt), 250);
            }
        } catch (SecurityException e) {
            readInFlight = false;
            log("Direct read failed: missing permission");
        }
    }

    private void subscribeBeaniePushCharacteristics(BluetoothGatt gatt) {
        BluetoothGattService beanieService = gatt.getService(BEANIE_SERVICE_UUID);
        if (beanieService == null) {
            log("No Beanie service UUID found for push subscription");
            return;
        }
        for (BluetoothGattCharacteristic ch : beanieService.getCharacteristics()) {
            int props = ch.getProperties();
            BluetoothGattDescriptor cccd = ch.getDescriptor(CCCD_UUID);
            if (cccd == null) continue;
            byte[] value = null;
            if ((props & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) {
                value = ENABLE_NOTIFY;
            } else if ((props & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
                value = ENABLE_INDICATE;
            }
            if (value == null) continue;

            try {
                boolean registered = gatt.setCharacteristicNotification(ch, true);
                log("Subscribe " + ch.getUuid() + " registered=" + registered + " value=" + hex(value));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    int writeStatus = gatt.writeDescriptor(cccd, value);
                    log("CCCD write start " + ch.getUuid() + " status=" + writeStatus);
                } else {
                    cccd.setValue(value);
                    boolean started = gatt.writeDescriptor(cccd);
                    log("CCCD write start " + ch.getUuid() + " started=" + started);
                }
            } catch (SecurityException e) {
                log("Subscribe failed: missing permission");
            }
        }
    }

    private void handleIncoming(String source, BluetoothGattCharacteristic characteristic, byte[] value) {
        if (value == null || value.length == 0) return;
        log(source + " payload " + characteristic.getUuid() + " len=" + value.length + " hex=" + hex(value));
        TemperatureCandidate candidate = decodeTemperature(value);
        if (candidate != null) {
            log(source + "_TEMP uuid=" + characteristic.getUuid() +
                " inner=" + two(candidate.innerC) +
                " outer=" + two(candidate.outerC) +
                " tskin=" + two(candidate.tskinC));
        }
    }

    private static TemperatureCandidate decodeTemperature(byte[] data) {
        for (int offset = 0; offset <= data.length - 4; offset++) {
            if (offset <= data.length - 5 && (data[offset] & 0xFF) == 0xA6) {
                TemperatureCandidate tagged = decodeWords(data, offset + 1);
                if (tagged != null) return tagged;
            }
            TemperatureCandidate legacy = decodeWords(data, offset);
            if (legacy != null) return legacy;
        }
        return null;
    }

    private static TemperatureCandidate decodeWords(byte[] data, int offset) {
        if (offset + 3 >= data.length) return null;
        int rawIn = (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
        int rawOut = (data[offset + 2] & 0xFF) | ((data[offset + 3] & 0xFF) << 8);
        if (rawIn == 0 && rawOut == 0) return null;
        TemperatureCandidate by128 = candidateFrom(rawIn, rawOut, 128.0);
        if (by128 != null) return by128;
        return candidateFrom(rawIn, rawOut, 16.0);
    }

    private static TemperatureCandidate candidateFrom(int rawIn, int rawOut, double scale) {
        double inner = (short) rawIn / scale;
        double outer = (short) rawOut / scale;
        if (!Double.isFinite(inner) || !Double.isFinite(outer)) return null;
        if (inner <= -5.0 || inner >= 60.0 || outer <= -15.0 || outer >= 60.0) return null;
        if (Math.abs(inner) < 0.5 && Math.abs(outer) < 0.5) return null;
        return new TemperatureCandidate(inner, outer, inner + 2.7 * (inner - outer));
    }

    private static String displayName(ScanResult result) {
        String scanName = result.getScanRecord() == null ? "" : result.getScanRecord().getDeviceName();
        if (scanName != null && !scanName.trim().isEmpty()) return scanName.trim();
        try {
            String deviceName = result.getDevice().getName();
            return deviceName == null ? "" : deviceName.trim();
        } catch (SecurityException e) {
            return "";
        }
    }

    private static boolean hasBeanieService(ScanResult result) {
        if (result.getScanRecord() == null || result.getScanRecord().getServiceUuids() == null) return false;
        for (ParcelUuid uuid : result.getScanRecord().getServiceUuids()) {
            if (BEANIE_SERVICE_UUID.equals(uuid.getUuid())) return true;
        }
        return false;
    }

    private static boolean isLikelyBeanieName(String name) {
        String normalized = name == null ? "" : name.toLowerCase(Locale.US);
        return normalized.contains("beanie") ||
            normalized.contains("v3") ||
            normalized.contains("v4") ||
            normalized.contains("v4e") ||
            normalized.contains("nrf");
    }

    private static String safeAddress(BluetoothGatt gatt) {
        try {
            return gatt.getDevice().getAddress();
        } catch (SecurityException e) {
            return "permission-denied";
        }
    }

    private static String props(int props) {
        StringBuilder out = new StringBuilder();
        if ((props & BluetoothGattCharacteristic.PROPERTY_READ) != 0) out.append("READ|");
        if ((props & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0) out.append("WRITE|");
        if ((props & BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) out.append("WRITE_NR|");
        if ((props & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) out.append("NOTIFY|");
        if ((props & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) out.append("INDICATE|");
        if (out.length() == 0) return String.valueOf(props);
        out.setLength(out.length() - 1);
        return out.toString();
    }

    private static String hex(byte[] bytes) {
        if (bytes == null) return "";
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            out.append(String.format(Locale.US, "%02X", b));
        }
        return out.toString();
    }

    private static String two(double value) {
        return String.format(Locale.US, "%.2f", value);
    }

    private void log(String message) {
        Log.i(TAG, message);
        runOnUiThread(() -> output.append(message + "\n"));
    }

    private static final class TemperatureCandidate {
        final double innerC;
        final double outerC;
        final double tskinC;

        TemperatureCandidate(double innerC, double outerC, double tskinC) {
            this.innerC = innerC;
            this.outerC = outerC;
            this.tskinC = tskinC;
        }
    }
}
