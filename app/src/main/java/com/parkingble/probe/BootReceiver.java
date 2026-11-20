package com.parkingble.probe;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
public final class BootReceiver extends BroadcastReceiver{
    @Override public void onReceive(Context c,Intent i){
        if(Intent.ACTION_BOOT_COMPLETED.equals(i.getAction()) && Beacon.enabled(c)){
            String result=Beacon.start(c,Beacon.firstMode(c));
            Events.add(c,"SYSTEM","BOOT_"+(result.startsWith("Фоновый")?"OK":"ERROR"),null,null);
        }
    }
}
