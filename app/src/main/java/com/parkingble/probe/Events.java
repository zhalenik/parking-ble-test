package com.parkingble.probe;

import android.content.Context;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.ArrayDeque;

public final class Events {
    private Events(){}
    public static File file(Context c){ return new File(c.getFilesDir(),"ble-events.csv"); }
    public static synchronized void add(Context c,String mode,String event,Integer rssi,Long dispatchMs) {
        File f=file(c);
        String date=new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ",Locale.US).format(new Date());
        String line=date+","+mode+","+event+","+(rssi==null?"":rssi)+","+(dispatchMs==null?"":dispatchMs)+"\n";
        try(FileOutputStream s=new FileOutputStream(f,true)){
            if(f.length()==0) s.write("timestamp,mode,event,rssi_dbm,dispatch_delay_ms\n".getBytes(StandardCharsets.UTF_8));
            s.write(line.getBytes(StandardCharsets.UTF_8));
        }catch(IOException e){ android.util.Log.e("ParkingBLE","CSV error",e); }
    }
    public static synchronized String tail(Context c,int n) {
        ArrayDeque<String> rows=new ArrayDeque<>();
        try(BufferedReader r=new BufferedReader(new InputStreamReader(new FileInputStream(file(c)),StandardCharsets.UTF_8))){
            String line;
            while((line=r.readLine())!=null) {
                if(line.startsWith("timestamp,"))continue;
                rows.addLast(line);
                if(rows.size()>n)rows.removeFirst();
            }
        }catch(IOException ignored){return "Событий пока нет";}
        StringBuilder b=new StringBuilder();
        while(!rows.isEmpty())b.append(rows.removeLast()).append('\n');
        return b.length()==0?"Событий пока нет":b.toString();
    }
}
