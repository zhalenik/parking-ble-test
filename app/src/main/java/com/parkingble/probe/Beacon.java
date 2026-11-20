package com.parkingble.probe;

import android.Manifest;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.ParcelUuid;
import java.util.Collections;
import java.util.UUID;

public final class Beacon {
    public static final UUID UUID_SERVICE = UUID.fromString("c6ec1c8d-e23a-4751-93f8-31d4d4a17b10");
    private static final String PREF = "bleprefs";
    public static final String ACTION = "com.parkingble.probe.SCAN";
    private Beacon() {}

    public static boolean permitted(Context c) {
        if (Build.VERSION.SDK_INT >= 31)
            return c.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED
                && c.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED
                && c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED;
        return c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED;
    }
    public static boolean backgroundLocationOK(Context c) {
        return Build.VERSION.SDK_INT<29 || Build.VERSION.SDK_INT>=31 ||
            c.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)==PackageManager.PERMISSION_GRANTED;
    }
    public static BluetoothLeScanner scanner(Context c) {
        BluetoothManager bm=(BluetoothManager)c.getSystemService(Context.BLUETOOTH_SERVICE);
        if (bm==null) return null;
        BluetoothAdapter adapter=bm.getAdapter();
        return adapter==null || !adapter.isEnabled()?null:adapter.getBluetoothLeScanner();
    }
    public static ScanFilter filter() {
        return new ScanFilter.Builder().setServiceUuid(new ParcelUuid(UUID_SERVICE)).build();
    }
    private static PendingIntent pending(Context c) {
        Intent i=new Intent(c,BleReceiver.class).setAction(ACTION);
        return PendingIntent.getBroadcast(c,4021,i,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_MUTABLE);
    }
    public static boolean enabled(Context c) {
        return c.getSharedPreferences(PREF,0).getBoolean("bg",false);
    }
    public static boolean firstMode(Context c) {
        return c.getSharedPreferences(PREF,0).getBoolean("first",true);
    }
    public static String start(Context c,boolean first) {
        if (!permitted(c)) return "Нет разрешений Bluetooth/геолокации";
        if (!backgroundLocationOK(c)) return "Android 10/11: в настройках разрешите геолокацию «Всегда»";
        try {
            BluetoothLeScanner s=scanner(c);
            if(s==null) return "Bluetooth выключен";
            s.stopScan(pending(c));
            ScanSettings.Builder b=new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER).setReportDelay(0)
                .setCallbackType(first ? ScanSettings.CALLBACK_TYPE_FIRST_MATCH | ScanSettings.CALLBACK_TYPE_MATCH_LOST
                                        : ScanSettings.CALLBACK_TYPE_ALL_MATCHES);
            if(first) b.setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                       .setNumOfMatches(ScanSettings.MATCH_NUM_ONE_ADVERTISEMENT);
            int rc=s.startScan(Collections.singletonList(filter()),b.build(),pending(c));
            if(rc!=0) return "Ошибка регистрации сканера: "+rc;
            c.getSharedPreferences(PREF,0).edit().putBoolean("bg",true).putBoolean("first",first).apply();
            Events.add(c,"BG","START_"+(first?"FIRST_MATCH":"ALL_MATCHES"),null,null);
            return "Фоновый скан зарегистрирован";
        } catch(Exception e) { return "Ошибка: "+e.toString(); }
    }
    public static String stop(Context c) {
        c.getSharedPreferences(PREF,0).edit().putBoolean("bg",false).apply();
        try {
            BluetoothLeScanner s=scanner(c);
            if(s!=null && permitted(c)) s.stopScan(pending(c));
            Events.add(c,"BG","STOP",null,null);
            return "Фоновый скан остановлен";
        } catch(Exception e) { return e.toString(); }
    }
}
