import me.hackalice.station.spotify.CommandParser;
import java.io.IOException;
public final class Check {
    static void expect(boolean condition){if(!condition)throw new AssertionError();}
    public static void main(String[] args)throws Exception{
        expect("Daft Punk".equals(CommandParser.parse("Алиса, включи в Спотифай Daft Punk")));
        expect("NCS".equals(CommandParser.parse("Включи NCS в Spotify")));
        expect(CommandParser.parse("Алиса, включи NCS в Саундклауде")==null);
        expect(CommandParser.parse("Алиса, включи свет")==null);
        expect("pause".equals(CommandParser.control("Алиса, стоп").command));
        expect("resume".equals(CommandParser.control("Алиса, продолжи").command));
        expect("next".equals(CommandParser.control("Алиса, следующий трек").command));
        expect("next".equals(CommandParser.control("Переключи трек").command));
        expect("previous".equals(CommandParser.control("Алиса, предыдущий трек.").command));
        expect(CommandParser.control("Алиса, перемотай на две минуты назад").seconds==-120);
        expect(CommandParser.control("перемотай на 30 секунд").seconds==30);
        expect(CommandParser.control("громкость один")==null);
        expect(SpotifyVoice.decode(SpotifyVoice.number(253,210)).number(253,0)==210);
        try{SpotifyVoice.decode(new byte[]{(byte)0x80});throw new AssertionError();}catch(IOException expected){}
        try{SpotifyVoice.decode(new byte[]{10,8,1});throw new AssertionError();}catch(IOException expected){}
        expect(SpotifyVoice.duplicate("same","стоп",1000,"same","стоп",500));
        expect(!SpotifyVoice.duplicate("same","продолжи",1000,"same","стоп",500));
        expect(!SpotifyVoice.duplicate("same","стоп",4000,"same","стоп",500));
        java.io.File temp=java.io.File.createTempFile("spotify-zip-check",".zip");
        java.io.File dest=new java.io.File(temp.getParentFile(),temp.getName()+"-out");expect(dest.mkdir());
        try{
            java.util.zip.ZipOutputStream zip=new java.util.zip.ZipOutputStream(new java.io.FileOutputStream(temp));
            for(String name:new String[]{"com.spotify.tv.android.apk","config.armeabi_v7a.apk","config.en.apk","config.ru.apk","config.xhdpi.apk"}){
                zip.putNextEntry(new java.util.zip.ZipEntry(name));zip.write(new byte[]{1,2,3});zip.closeEntry();
            }
            zip.close();SpotifyControl.extract(temp.getPath(),dest.getPath());
            for(java.io.File file:dest.listFiles())expect(file.length()==3);
            expect(dest.listFiles().length==5);
        }finally{for(java.io.File file:dest.listFiles())file.delete();dest.delete();temp.delete();}
        System.out.println("Spotify parser and bounded IPC decoder: OK");
    }
}
