package com.parkingble.probe;

import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.SystemClock;
import java.util.ArrayList;

public final class BleReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c,Intent i) {
        if(!Beacon.ACTION.equals(i.getAction()))return;
        int err=i.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE,0);
        if(err!=0){ Events.add(c,"BG","SCAN_ERROR_"+err,null,null); return; }
        ArrayList<ScanResult> results;
        if(Build.VERSION.SDK_INT>=33) results=i.getParcelableArrayListExtra(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT,ScanResult.class);
        else results=i.getParcelableArrayListExtra(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT);
        if(results==null || results.isEmpty())return;
        int type=i.getIntExtra(BluetoothLeScanner.EXTRA_CALLBACK_TYPE,0);
        String event=(type & ScanSettings.CALLBACK_TYPE_MATCH_LOST)!=0 ? "LOST":
                     (type & ScanSettings.CALLBACK_TYPE_FIRST_MATCH)!=0 ? "FOUND":"MATCH";
        long now=SystemClock.elapsedRealtimeNanos();
        for(ScanResult r:results) {
            if(type==ScanSettings.CALLBACK_TYPE_ALL_MATCHES){
                long millis=SystemClock.elapsedRealtime();
                long last=c.getSharedPreferences("bleprefs",0).getLong("last_sample",0);
                if(millis-last<2000)continue;
                c.getSharedPreferences("bleprefs",0).edit().putLong("last_sample",millis).apply();
            }
            long delta=now-r.getTimestampNanos();
            Long latency=delta>=0 && delta<3_600_000_000_000L ? delta/1_000_000L:null;
            Events.add(c,"BG",event,r.getRssi(),latency);
        }
    }
}
