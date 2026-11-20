package com.parkingble.probe;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.util.Collections;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int EXPORT=1234;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private TextView info, readings, logs;
    private BluetoothLeScanner liveScanner;
    private boolean live;
    private int rssi=Integer.MIN_VALUE;
    private long lastLog;
    private final Runnable updater=new Runnable(){
        @Override public void run(){refresh();handler.postDelayed(this,1200);}
    };
    private final ScanCallback callback=new ScanCallback(){
        @Override public void onScanResult(int type,ScanResult r){
            rssi=r.getRssi();
            long now=SystemClock.elapsedRealtime();
            if(now-lastLog>1500) {
                long delta=SystemClock.elapsedRealtimeNanos()-r.getTimestampNanos();
                Events.add(MainActivity.this,"LIVE","MATCH",rssi,
                    delta>=0&&delta<3_600_000_000_000L?delta/1_000_000L:null);
                lastLog=now;
            }
            refresh();
        }
        @Override public void onScanFailed(int error){
            live=false;
            Events.add(MainActivity.this,"LIVE","ERROR_"+error,null,null);
            refresh();
        }
    };

    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        ScrollView scroll=new ScrollView(this);
        scroll.setBackgroundColor(0xFFF3F5FA);
        LinearLayout page=new LinearLayout(this);
        page.setPadding(24,30,24,28);
        page.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(page);
        TextView heading=label("Parking BLE Probe",26);
        heading.setTextColor(0xFF172A4B);
        page.addView(heading);
        page.addView(label("ESP32-C3 SuperMini · BLE diagnostic",14));
        page.addView(label("Service UUID: "+Beacon.UUID_SERVICE,12));
        info=label("",15);page.addView(info);
        readings=label("",24);page.addView(readings);
        addButton(page,"Выдать разрешения",this::askPermissions);
        addButton(page,"Запустить ФОН: FOUND / LOST",()->show(Beacon.start(this,true)));
        addButton(page,"Запустить ФОН: ALL_MATCHES",()->show(Beacon.start(this,false)));
        addButton(page,"Остановить фоновый скан",()->show(Beacon.stop(this)));
        addButton(page,"Запустить живой RSSI-тест",this::startLive);
        addButton(page,"Остановить живой тест",this::stopLive);
        addButton(page,"Поставить временную метку",()->{
            Events.add(this,"MANUAL","MARK",null,null);refresh();
        });
        addButton(page,"Экспортировать CSV",this::exportCsv);
        addButton(page,"Открыть настройки приложения",()->startActivity(
            new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:"+getPackageName()))));
        page.addView(label("Последние события (новые сверху)",14));
        logs=label("",12);
        logs.setTextIsSelectable(true);
        page.addView(logs);
        page.addView(label(
            "Проверка: включите фоновый режим, погасите экран, отойдите от ESP32, "
           +"затем приблизьтесь. После испытаний экспортируйте CSV. "
           +"dispatch_delay_ms — задержка передачи BLE-события приложению, "
           +"НЕ время от появления телефона на расстоянии 5 метров.",12));
        setContentView(scroll);
        refresh();
    }
    private TextView label(String s,int size){
        TextView t=new TextView(this);t.setText(s);t.setTextSize(size);
        t.setTextColor(0xFF27364B);t.setPadding(0,10,0,10);return t;
    }
    private void addButton(LinearLayout page,String title,Runnable task){
        Button button=new Button(this);button.setAllCaps(false);button.setText(title);
        button.setOnClickListener(v->{task.run();refresh();});
        page.addView(button);
    }
    private void refresh(){
        if(info==null)return;
        info.setText("Разрешения: "+(Beacon.permitted(this)?"OK":"НЕ ВЫДАНЫ")
            +"\nФоновая геолокация (Android 10/11): "+(Beacon.backgroundLocationOK(this)?"OK":"НЕ ВЫДАНА")
            +"\nФон: "+(Beacon.enabled(this)?(Beacon.firstMode(this)?"FIRST_MATCH/LOST":"ALL_MATCHES"):"выключен")
            +"\nЖивой режим: "+(live?"включен":"выключен"));
        readings.setText(rssi==Integer.MIN_VALUE?"RSSI: —":String.format(Locale.US,"RSSI: %d dBm",rssi));
        logs.setText(Events.tail(this,15));
    }
    private void askPermissions(){
        if(Build.VERSION.SDK_INT>=31)requestPermissions(new String[]{
            Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.ACCESS_FINE_LOCATION},21);
        else requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION},21);
        if(Build.VERSION.SDK_INT>=29 && Build.VERSION.SDK_INT<=30)
            toast("Android 10/11: дополнительно включите геолокацию «Всегда» в настройках приложения");
    }
    private void startLive(){
        if(!Beacon.permitted(this)){toast("Сначала выдайте разрешения");return;}
        if(live)return;
        if(Beacon.enabled(this))Beacon.stop(this);
        try{
            liveScanner=Beacon.scanner(this);
            if(liveScanner==null){toast("Включите Bluetooth");return;}
            ScanSettings settings=new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES).build();
            liveScanner.startScan(Collections.singletonList(Beacon.filter()),settings,callback);
            live=true;rssi=Integer.MIN_VALUE;lastLog=0;
            Events.add(this,"LIVE","START",null,null);
        }catch(Exception e){live=false;toast(e.toString());}
    }
    private void stopLive(){
        if(!live)return;
        try{if(liveScanner!=null && Beacon.permitted(this))liveScanner.stopScan(callback);}
        catch(Exception ignored){}
        live=false;liveScanner=null;
        Events.add(this,"LIVE","STOP",null,null);
    }
    @Override protected void onResume(){
        super.onResume();handler.removeCallbacks(updater);handler.post(updater);
    }
    @Override protected void onPause(){
        handler.removeCallbacks(updater);
        // Живой скан работает только когда окно открыто.
        stopLive();super.onPause();
    }
    private void exportCsv(){
        if(!Events.file(this).exists()){toast("Журнал пуст");return;}
        Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("text/csv");
        i.putExtra(Intent.EXTRA_TITLE,"parking-ble-events.csv");
        startActivityForResult(i,EXPORT);
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(request!=EXPORT||result!=RESULT_OK||data==null||data.getData()==null)return;
        try(FileInputStream in=new FileInputStream(Events.file(this));
            OutputStream out=getContentResolver().openOutputStream(data.getData())){
            if(out==null)throw new IllegalStateException("Can't open file");
            byte[] buf=new byte[8192];int n;
            while((n=in.read(buf))!=-1)out.write(buf,0,n);
            toast("CSV сохранён");
        }catch(Exception e){toast(e.toString());}
    }
    private void show(String s){toast(s);refresh();}
    private void toast(String s){Toast.makeText(this,s,Toast.LENGTH_LONG).show();}
}
