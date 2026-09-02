package com.crownparkcomputing.retroatarist;

import android.app.NativeActivity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.database.Cursor;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;
import android.view.View;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Android platform broker. Every visible screen is rendered by Dear ImGui. */
public final class RetroAtariSTActivity extends NativeActivity {
    private static final String TAG = "RetroAtariST";
    private static final String RETROMEDIA_URL = "https://media.crownparkcomputing.com";
    private static final String RETROMEDIA_PREFS = "retromedia_private";
    private static final String RETROMEDIA_KEY_ALIAS =
            "com.crownparkcomputing.retroatarist.retromedia.session";
    private static final int MAX_REPLY_BYTES = 4 * 1024 * 1024;
    private static final int MAX_ART_BYTES = 32 * 1024 * 1024;
    private static final int OPEN_ROM = 7100;
    private static final int OPEN_SOFTWARE = 7101;
    private static final Set<String> CARD_TYPES = new HashSet<>();

    static {
        CARD_TYPES.add("box2d");
        CARD_TYPES.add("images");
        CARD_TYPES.add("thumbnails");
        CARD_TYPES.add("titles");
        System.loadLibrary("retro_atarist");
    }

    private static native void nativeDocumentImported(int kind, String path);

    private File workDirectory;
    private File tosDirectory;
    private File gamesDirectory;
    private volatile String retroMediaResult;
    private volatile String retroMediaCatalogueResult = "";
    private volatile String downloadedPath = "";
    private volatile boolean retroMediaBusy;
    private volatile long retroMediaDownloadBytes;
    private volatile long retroMediaDownloadTotal;

    @Override
    protected void onCreate(Bundle state) {
        prepareStorage();
        super.onCreate(state);
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    private void prepareStorage() {
        workDirectory = new File(getFilesDir(), "Core");
        tosDirectory = new File(getFilesDir(), "TOS");
        File external = getExternalFilesDir(null);
        gamesDirectory = new File(external != null ? external : getFilesDir(), "AtariST/Games");
        workDirectory.mkdirs();
        tosDirectory.mkdirs();
        gamesDirectory.mkdirs();
        File emutos = new File(tosDirectory, "EmuTOS 1.4 UK.img");
        if (!emutos.isFile()) {
            try (InputStream input = getAssets().open("emutos-1.4-uk.img");
                 OutputStream output = new FileOutputStream(emutos)) {
                copy(input, output);
            } catch (Exception error) {
                Log.e(TAG, "Unable to install bundled EmuTOS", error);
            }
        }
        File demo = new File(workDirectory, "retro-atarist-core-demo.st");
        if (!demo.isFile()) {
            try (InputStream input = getAssets().open("retro-atarist-core-demo.st");
                 OutputStream output = new FileOutputStream(demo)) {
                copy(input, output);
            } catch (Exception error) {
                Log.e(TAG, "Unable to install bundled core demo", error);
            }
        }
    }

    public String getWorkDirectory() { return workDirectory.getAbsolutePath(); }
    public String getTosDirectory() { return tosDirectory.getAbsolutePath(); }
    public String getGamesDirectory() { return gamesDirectory.getAbsolutePath(); }

    public String getBrandLogoPath() {
        File target = new File(workDirectory, "retro-atarist-logo.r3ar");
        try (InputStream input = getAssets().open("retro-atarist-logo.png")) {
            Bitmap bitmap = BitmapFactory.decodeStream(input);
            if (bitmap == null) throw new Exception("Brand logo could not be decoded");
            writeArtwork(bitmap, target);
            bitmap.recycle();
            return target.getAbsolutePath();
        } catch (Exception error) {
            Log.e(TAG, "Unable to prepare brand logo", error);
            return "";
        }
    }

    public void openDocumentPicker(int kind) {
        runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivityForResult(intent, kind == 0 ? OPEN_ROM : OPEN_SOFTWARE);
        });
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent result) {
        super.onActivityResult(requestCode, resultCode, result);
        if ((requestCode != OPEN_ROM && requestCode != OPEN_SOFTWARE)
                || resultCode != RESULT_OK || result == null || result.getData() == null) return;
        final int kind = requestCode == OPEN_ROM ? 0 : 1;
        final Uri source = result.getData();
        new Thread(() -> {
            try {
                File directory = kind == 0 ? tosDirectory : gamesDirectory;
                File target = uniqueFile(directory, displayName(source));
                try (InputStream input = getContentResolver().openInputStream(source);
                     OutputStream output = new FileOutputStream(target)) {
                    if (input == null) throw new Exception("Selected file cannot be opened");
                    copy(input, output);
                }
                nativeDocumentImported(kind, target.getAbsolutePath());
            } catch (Exception error) {
                Log.e(TAG, "Import failed", error);
            }
        }, "RetroAtariST-import").start();
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(uri,
                new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) return cursor.getString(0);
        } catch (Exception ignored) {}
        String name = uri.getLastPathSegment();
        return name == null || name.isEmpty() ? "imported.bin" : name;
    }

    private static File uniqueFile(File directory, String requested) {
        String safe = safeFileName(requested);
        File candidate = new File(directory, safe);
        if (!candidate.exists()) return candidate;
        int dot = safe.lastIndexOf('.');
        String stem = dot > 0 ? safe.substring(0, dot) : safe;
        String extension = dot > 0 ? safe.substring(dot) : "";
        for (int index = 2; index < 10000; ++index) {
            candidate = new File(directory, stem + " " + index + extension);
            if (!candidate.exists()) return candidate;
        }
        return new File(directory, System.currentTimeMillis() + extension);
    }

    private static void copy(InputStream input, OutputStream output) throws Exception {
        byte[] buffer = new byte[64 * 1024];
        int count;
        while ((count = input.read(buffer)) > 0) output.write(buffer, 0, count);
    }

    // --- Calls made by the native ImGui host ----------------------------

    public void retroMediaStatus() {
        startRetroMediaTask("STATUS", () -> {
            if (loadRetroMediaSession().isEmpty()
                    && !BuildConfig.RETROMEDIA_EMAIL.isEmpty()
                    && !BuildConfig.RETROMEDIA_PASSWORD.isEmpty()) {
                retroMediaLoginImpl(BuildConfig.RETROMEDIA_EMAIL, BuildConfig.RETROMEDIA_PASSWORD);
            } else {
                retroMediaStatusImpl();
            }
        });
    }

    public void retroMediaLogin(String email, String password) {
        startRetroMediaTask("LOGIN", () -> retroMediaLoginImpl(email, password));
    }

    public void retroMediaLogout() {
        startRetroMediaTask("LOGOUT", this::retroMediaLogoutImpl);
    }

    public void retroMediaSync(String gameNames, String mediaType) {
        startRetroMediaTask("SYNC", () -> retroMediaSyncImpl(gameNames, mediaType));
    }

    public void retroMediaBrowse(String search) {
        startRetroMediaTask("CATALOGUE", () -> retroMediaBrowseImpl(search));
    }

    public void retroMediaDownload(String slug) {
        retroMediaDownloadBytes = 0;
        retroMediaDownloadTotal = 0;
        startRetroMediaTask("DOWNLOAD", () -> retroMediaDownloadImpl(slug));
    }

    public String consumeRetroMediaResult() {
        String result = retroMediaResult;
        retroMediaResult = null;
        return result == null ? "" : result;
    }

    public String retroMediaCatalogueResult() { return retroMediaCatalogueResult; }

    public String consumeDownloadedPath() {
        String path = downloadedPath;
        downloadedPath = "";
        return path;
    }

    public String retroMediaDownloadProgress() {
        return retroMediaDownloadBytes + "|" + retroMediaDownloadTotal;
    }

    public String retroMediaArtwork(String mediaType) {
        if (!CARD_TYPES.contains(mediaType)) return "";
        String prefix = "art." + mediaType + ".";
        StringBuilder output = new StringBuilder();
        for (Map.Entry<String, ?> entry : retroMediaPreferences().getAll().entrySet()) {
            if (!entry.getKey().startsWith(prefix) || !(entry.getValue() instanceof String)) continue;
            String[] fields = ((String)entry.getValue()).split("\\|", 5);
            if (fields.length < 4 || !new File(fields[1]).isFile()) continue;
            output.append(safeResultField(fields[0])).append('|')
                    .append(fields[1]).append('|').append(fields[2]).append('|')
                    .append(fields[3]).append('\n');
        }
        return output.toString();
    }

    // --- RetroMedia implementation --------------------------------------

    private interface RetroMediaWork { void run() throws Exception; }

    private static final class HttpReply {
        int status;
        byte[] body;
        String cookie;
    }

    private void startRetroMediaTask(String operation, RetroMediaWork work) {
        synchronized (this) {
            if (retroMediaBusy) {
                retroMediaResult = result(false, operation, "", 0, 0, 0, 0,
                        false, "Another RetroMedia operation is running");
                return;
            }
            retroMediaBusy = true;
            retroMediaResult = null;
        }
        new Thread(() -> {
            try {
                work.run();
            } catch (Exception error) {
                retroMediaResult = result(false, operation, "", 0, 0, 0, 0,
                        false, usefulError(error));
                Log.e(TAG, "RetroMedia " + operation + " failed", error);
            } finally {
                retroMediaBusy = false;
            }
        }, "RetroAtariST-retromedia-" + operation.toLowerCase(Locale.ROOT)).start();
    }

    private static String usefulError(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? error.getClass().getSimpleName() : message;
    }

    private static String result(boolean ok, String operation, String email, int credits,
                                 int free, int matched, int downloaded, boolean admin,
                                 String message) {
        return (ok ? "OK" : "ERROR") + "|" + safeResultField(operation) + "|"
                + safeResultField(email) + "|" + credits + "|" + free + "|"
                + matched + "|" + downloaded + "|" + (admin ? "1" : "0") + "|"
                + safeResultField(message);
    }

    private static String safeResultField(String text) {
        return text == null ? "" : text.replace('|', ' ').replace('\n', ' ').replace('\r', ' ');
    }

    private SharedPreferences retroMediaPreferences() {
        return getSharedPreferences(RETROMEDIA_PREFS, MODE_PRIVATE);
    }

    private SecretKey retroMediaSecretKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (store.containsAlias(RETROMEDIA_KEY_ALIAS)) {
            return ((KeyStore.SecretKeyEntry)store.getEntry(RETROMEDIA_KEY_ALIAS, null)).getSecretKey();
        }
        KeyGenerator generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(RETROMEDIA_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
        return generator.generateKey();
    }

    private String encryptSession(String session) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, retroMediaSecretKey());
        byte[] encrypted = cipher.doFinal(session.getBytes(StandardCharsets.UTF_8));
        return Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + "."
                + Base64.encodeToString(encrypted, Base64.NO_WRAP);
    }

    private String decryptSession(String stored) {
        try {
            int separator = stored.indexOf('.');
            if (separator <= 0) return "";
            byte[] iv = Base64.decode(stored.substring(0, separator), Base64.NO_WRAP);
            byte[] encrypted = Base64.decode(stored.substring(separator + 1), Base64.NO_WRAP);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, retroMediaSecretKey(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (Exception error) {
            clearRetroMediaSession();
            return "";
        }
    }

    private void saveRetroMediaSession(String cookie, String email) throws Exception {
        retroMediaPreferences().edit().putString("session", encryptSession(cookie))
                .putString("email", email == null ? "" : email).apply();
    }

    private String loadRetroMediaSession() {
        String stored = retroMediaPreferences().getString("session", "");
        return stored.isEmpty() ? "" : decryptSession(stored);
    }

    private void clearRetroMediaSession() {
        retroMediaPreferences().edit().remove("session").apply();
    }

    private static byte[] readLimited(InputStream input, int maximum) throws Exception {
        if (input == null) return new byte[0];
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[64 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) > 0) {
            total += count;
            if (total > maximum) throw new Exception("RetroMedia response is too large");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private HttpReply request(String method, String address, JSONObject body,
                              String cookie, int maximum) throws Exception {
        HttpURLConnection connection = (HttpURLConnection)new URL(address).openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(60000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Accept", "application/json, image/*, application/zip");
        connection.setRequestProperty("User-Agent", "Retro-AtariST/1.0 Android RetroMedia client");
        if (cookie != null && !cookie.isEmpty()) connection.setRequestProperty("Cookie", cookie);
        if (body != null) {
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream output = connection.getOutputStream()) { output.write(bytes); }
        }
        HttpReply reply = new HttpReply();
        reply.status = connection.getResponseCode();
        reply.cookie = connection.getHeaderField("Set-Cookie");
        InputStream input = reply.status >= 400 ? connection.getErrorStream() : connection.getInputStream();
        try { reply.body = readLimited(input, maximum); }
        finally {
            if (input != null) input.close();
            connection.disconnect();
        }
        return reply;
    }

    private static String text(HttpReply reply) {
        return new String(reply.body == null ? new byte[0] : reply.body, StandardCharsets.UTF_8);
    }

    private static String apiError(HttpReply reply) {
        try {
            String error = new JSONObject(text(reply)).optString("error", "");
            if (!error.isEmpty()) return error;
        } catch (Exception ignored) {}
        return "RetroMedia returned HTTP " + reply.status;
    }

    private static String sessionCookie(String setCookie) {
        if (setCookie == null) return "";
        for (String part : setCookie.split(";")) {
            String value = part.trim();
            if (value.startsWith("rm_session=")) return value;
        }
        return "";
    }

    private JSONObject fetchAccount(String cookie) throws Exception {
        HttpReply reply = request("GET", RETROMEDIA_URL + "/api/me", null, cookie, MAX_REPLY_BYTES);
        if (reply.status == 401 || reply.status == 403) {
            clearRetroMediaSession();
            throw new Exception("RetroMedia session expired — sign in again");
        }
        if (reply.status != 200) throw new Exception(apiError(reply));
        return new JSONObject(text(reply)).getJSONObject("account");
    }

    private void publish(String operation, JSONObject account, int matched,
                         int downloaded, String message) {
        retroMediaResult = result(true, operation, account.optString("email", ""),
                account.optInt("credits", 0), account.optInt("freeRemainingToday", 0),
                matched, downloaded, account.optBoolean("isAdmin", false), message);
    }

    private void retroMediaStatusImpl() throws Exception {
        String cookie = loadRetroMediaSession();
        if (cookie.isEmpty()) {
            retroMediaResult = result(true, "STATUS",
                    retroMediaPreferences().getString("email", ""), 0, 0, 0, 0,
                    false, "Not signed in");
            return;
        }
        publish("STATUS", fetchAccount(cookie), 0, 0, "Connected");
    }

    private void retroMediaLoginImpl(String email, String password) throws Exception {
        email = email == null ? "" : email.trim();
        password = password == null ? "" : password;
        if (email.isEmpty() || password.isEmpty()) throw new Exception("Enter email and password");
        HttpReply configReply = request("GET", RETROMEDIA_URL + "/api/auth/config",
                null, "", MAX_REPLY_BYTES);
        if (configReply.status != 200) throw new Exception(apiError(configReply));
        JSONObject firebase = new JSONObject(text(configReply)).optJSONObject("firebase");
        if (firebase == null || !firebase.optBoolean("enabled", false)) {
            throw new Exception("RetroMedia Firebase sign-in is not configured");
        }
        String apiKey = firebase.optString("apiKey", "");
        JSONObject credentials = new JSONObject();
        credentials.put("email", email);
        credentials.put("password", password);
        credentials.put("returnSecureToken", true);
        HttpReply identity = request("POST",
                "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
                        + URLEncoder.encode(apiKey, "UTF-8"), credentials, "", MAX_REPLY_BYTES);
        if (identity.status != 200) throw new Exception("Wrong RetroMedia email or password");
        JSONObject exchange = new JSONObject();
        exchange.put("id_token", new JSONObject(text(identity)).getString("idToken"));
        HttpReply login = request("POST", RETROMEDIA_URL + "/api/auth/firebase",
                exchange, "", MAX_REPLY_BYTES);
        if (login.status != 200) throw new Exception(apiError(login));
        String cookie = sessionCookie(login.cookie);
        if (cookie.isEmpty()) throw new Exception("RetroMedia did not return a session");
        JSONObject account = new JSONObject(text(login)).getJSONObject("account");
        saveRetroMediaSession(cookie, account.optString("email", email));
        publish("LOGIN", account, 0, 0, "Signed in");
    }

    private void retroMediaLogoutImpl() throws Exception {
        String cookie = loadRetroMediaSession();
        if (!cookie.isEmpty()) request("POST", RETROMEDIA_URL + "/api/auth/logout",
                new JSONObject(), cookie, MAX_REPLY_BYTES);
        clearRetroMediaSession();
        retroMediaCatalogueResult = "";
        retroMediaResult = result(true, "LOGOUT",
                retroMediaPreferences().getString("email", ""), 0, 0, 0, 0,
                false, "Signed out");
    }

    private static String canonical(String name) {
        if (name == null) return "";
        String value = name.toLowerCase(Locale.ROOT)
                .replaceAll("\\([^)]*\\)", " ").replaceAll("\\[[^]]*\\]", " ")
                .replace('&', ' ').replaceAll("[^a-z0-9]+", " ").trim()
                .replaceAll("\\s+", " ");
        if (value.startsWith("the ")) value = value.substring(4);
        if (value.endsWith(" the")) value = value.substring(0, value.length() - 4);
        return value;
    }

    private static int editDistance(String left, String right) {
        int[] previous = new int[right.length() + 1];
        int[] current = new int[right.length() + 1];
        for (int i = 0; i <= right.length(); ++i) previous[i] = i;
        for (int row = 1; row <= left.length(); ++row) {
            current[0] = row;
            for (int column = 1; column <= right.length(); ++column) {
                current[column] = Math.min(Math.min(current[column - 1] + 1,
                        previous[column] + 1), previous[column - 1]
                        + (left.charAt(row - 1) == right.charAt(column - 1) ? 0 : 1));
            }
            int[] swap = previous; previous = current; current = swap;
        }
        return previous[right.length()];
    }

    private static JSONObject bestMatch(String localName, ArrayList<JSONObject> catalogue) {
        String wanted = canonical(localName);
        JSONObject best = null;
        double bestScore = 0.0;
        for (JSONObject game : catalogue) {
            String candidate = canonical(game.optString("title", game.optString("name", "")));
            if (candidate.isEmpty()) continue;
            int longest = Math.max(wanted.length(), candidate.length());
            double score = longest == 0 ? 0.0
                    : 1.0 - (double)editDistance(wanted, candidate) / longest;
            if (score > bestScore) { bestScore = score; best = game; }
            if (score == 1.0) break;
        }
        return bestScore >= 0.86 ? best : null;
    }

    private ArrayList<JSONObject> artworkCatalogue(String mediaType) throws Exception {
        ArrayList<JSONObject> output = new ArrayList<>();
        for (int page = 1; page <= 20; ++page) {
            String address = RETROMEDIA_URL + "/api/systems/atarist/games?limit=200&page="
                    + page + "&type=" + URLEncoder.encode(mediaType, "UTF-8");
            HttpReply reply = request("GET", address, null, "", MAX_REPLY_BYTES);
            if (reply.status != 200) throw new Exception(apiError(reply));
            JSONObject root = new JSONObject(text(reply));
            JSONArray games = root.getJSONArray("games");
            for (int index = 0; index < games.length(); ++index) output.add(games.getJSONObject(index));
            if (games.length() == 0 || output.size() >= root.optInt("total", output.size())) break;
        }
        return output;
    }

    private static String sha256(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder output = new StringBuilder();
        for (byte item : digest) output.append(String.format(Locale.ROOT, "%02x", item));
        return output.toString();
    }

    private File artworkDirectory(String mediaType) {
        return new File(new File(getFilesDir(), "retromedia-art"), mediaType);
    }

    private static Bitmap firstImage(byte[] zipBytes) throws Exception {
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (entry.isDirectory()) continue;
                String name = entry.getName().toLowerCase(Locale.ROOT);
                if (!(name.endsWith(".png") || name.endsWith(".jpg")
                        || name.endsWith(".jpeg") || name.endsWith(".webp")
                        || name.endsWith(".bmp"))) continue;
                byte[] image = readLimited(zip, MAX_ART_BYTES);
                Bitmap bitmap = BitmapFactory.decodeByteArray(image, 0, image.length);
                if (bitmap != null) return bitmap;
            }
        }
        throw new Exception("Artwork archive contains no image");
    }

    private static void writeArtwork(Bitmap source, File target) throws Exception {
        double ratio = Math.min(1.0, Math.min(360.0 / source.getWidth(), 500.0 / source.getHeight()));
        Bitmap bitmap = ratio < 1.0 ? Bitmap.createScaledBitmap(source,
                Math.max(1, (int)Math.round(source.getWidth() * ratio)),
                Math.max(1, (int)Math.round(source.getHeight() * ratio)), true) : source;
        int width = bitmap.getWidth();
        int[] pixels = new int[width];
        byte[] rgba = new byte[width * 4];
        try (DataOutputStream output = new DataOutputStream(new FileOutputStream(target))) {
            output.write(new byte[] {'R', '3', 'A', 'R'});
            output.writeInt(width);
            output.writeInt(bitmap.getHeight());
            for (int y = 0; y < bitmap.getHeight(); ++y) {
                bitmap.getPixels(pixels, 0, width, 0, y, width, 1);
                for (int x = 0; x < width; ++x) {
                    int argb = pixels[x];
                    int at = x * 4;
                    rgba[at] = (byte)(argb >>> 16);
                    rgba[at + 1] = (byte)(argb >>> 8);
                    rgba[at + 2] = (byte)argb;
                    rgba[at + 3] = (byte)(argb >>> 24);
                }
                output.write(rgba);
            }
        }
        if (bitmap != source) bitmap.recycle();
        source.recycle();
    }

    private void retroMediaSyncImpl(String gameNames, String mediaType) throws Exception {
        if (!CARD_TYPES.contains(mediaType)) throw new Exception("Unsupported artwork type");
        String cookie = loadRetroMediaSession();
        if (cookie.isEmpty()) throw new Exception("Sign in to RetroMedia first");
        ArrayList<JSONObject> catalogue = artworkCatalogue(mediaType);
        File folder = artworkDirectory(mediaType);
        if (!folder.isDirectory() && !folder.mkdirs()) throw new Exception("Cannot create artwork cache");
        int matched = 0;
        int downloaded = 0;
        int missing = 0;
        for (String localName : gameNames.split("\\n")) {
            if (localName.trim().isEmpty()) continue;
            String key = "art." + mediaType + "." + sha256(localName);
            File target = new File(folder, sha256(localName) + ".r3a");
            String existing = retroMediaPreferences().getString(key, "");
            if (target.isFile() && !existing.isEmpty()) { ++matched; continue; }
            JSONObject match = bestMatch(localName, catalogue);
            if (match == null || match.optString("preview", "").isEmpty()) { ++missing; continue; }
            ++matched;
            String slug = match.getString("slug");
            String address = RETROMEDIA_URL + "/api/systems/atarist/games/"
                    + URLEncoder.encode(slug, "UTF-8").replace("+", "%20")
                    + "/zip?types=" + URLEncoder.encode(mediaType, "UTF-8");
            HttpReply zip = request("GET", address, null, cookie, MAX_ART_BYTES);
            if (zip.status != 200) { ++missing; continue; }
            writeArtwork(firstImage(zip.body), target);
            try (DataInputStream input = new DataInputStream(new FileInputStream(target))) {
                input.skipBytes(4);
                int width = input.readInt();
                int height = input.readInt();
                retroMediaPreferences().edit().putString(key,
                        localName + "|" + target.getAbsolutePath() + "|" + width + "|" + height
                                + "|" + safeResultField(slug)).apply();
            }
            ++downloaded;
        }
        JSONObject account = fetchAccount(cookie);
        publish("SYNC", account, matched, downloaded,
                downloaded + " downloaded, " + missing + " not found");
    }

    private void retroMediaBrowseImpl(String search) throws Exception {
        String cookie = loadRetroMediaSession();
        if (cookie.isEmpty()) throw new Exception("Sign in to RetroMedia first");
        JSONObject account = fetchAccount(cookie);
        if (!account.optBoolean("isAdmin", false)) throw new Exception("Administrator account required");
        StringBuilder output = new StringBuilder();
        int found = 0;
        for (int page = 1; page <= 20; ++page) {
            String address = RETROMEDIA_URL
                    + "/api/systems/atarist/games?limit=200&category=rom&page=" + page;
            if (search != null && !search.trim().isEmpty()) {
                address += "&search=" + URLEncoder.encode(search.trim(), "UTF-8");
            }
            HttpReply reply = request("GET", address, null, cookie, MAX_REPLY_BYTES);
            if (reply.status != 200) throw new Exception(apiError(reply));
            JSONObject root = new JSONObject(text(reply));
            JSONArray games = root.getJSONArray("games");
            for (int index = 0; index < games.length(); ++index) {
                JSONObject game = games.getJSONObject(index);
                int files = game.optJSONObject("availability") == null ? 0
                        : game.getJSONObject("availability").optInt("romFiles", 0);
                if (files <= 0) continue;
                output.append(safeResultField(game.optString("slug", ""))).append('|')
                        .append(safeResultField(game.optString("title", game.optString("name", ""))))
                        .append('|').append(files).append('|')
                        .append(game.optLong("totalBytes", 0)).append('\n');
                ++found;
            }
            if (games.length() == 0 || page * 200 >= root.optInt("total", found)) break;
        }
        retroMediaCatalogueResult = output.toString();
        publish("CATALOGUE", account, found, 0, found + " downloadable games");
    }

    private static String safeFileName(String name) {
        if (name == null) return "game.bin";
        int slash = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
        if (slash >= 0) name = name.substring(slash + 1);
        name = name.replaceAll("[\\p{Cntrl}\\/:*?\"<>|]", "_").trim();
        return name.isEmpty() || name.equals(".") || name.equals("..") ? "game.bin" : name;
    }

    private static boolean supportedGame(String name) {
        String lower = name.toLowerCase(Locale.ROOT);
        return lower.endsWith(".st") || lower.endsWith(".msa") || lower.endsWith(".dim")
                || lower.endsWith(".stx") || lower.endsWith(".ipf") || lower.endsWith(".img")
                || lower.endsWith(".zip");
    }

    private File writeGame(File folder, String name, InputStream input) throws Exception {
        File target = uniqueFile(folder, safeFileName(name));
        try (OutputStream output = new FileOutputStream(target)) { copy(input, output); }
        return target;
    }

    private void retroMediaDownloadImpl(String slug) throws Exception {
        String cookie = loadRetroMediaSession();
        if (cookie.isEmpty()) throw new Exception("Sign in to RetroMedia first");
        JSONObject account = fetchAccount(cookie);
        if (!account.optBoolean("isAdmin", false)) throw new Exception("Administrator account required");
        String encoded = URLEncoder.encode(slug, "UTF-8").replace("+", "%20");
        HttpReply detailReply = request("GET", RETROMEDIA_URL
                + "/api/systems/atarist/games/" + encoded, null, cookie, MAX_REPLY_BYTES);
        if (detailReply.status != 200) throw new Exception(apiError(detailReply));
        JSONObject detail = new JSONObject(text(detailReply));
        JSONArray roms = detail.optJSONArray("roms");
        if (roms == null || roms.length() == 0) throw new Exception("No game files available");
        String title = detail.optString("title", detail.optString("name", slug));
        File destination = uniqueFile(gamesDirectory, safeFileName(title));
        if (!destination.mkdirs()) throw new Exception("Cannot create game folder");
        HttpURLConnection connection = (HttpURLConnection)new URL(RETROMEDIA_URL
                + "/api/systems/atarist/games/" + encoded + "/zip?types=rom").openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(10 * 60 * 1000);
        connection.setRequestProperty("Cookie", cookie);
        connection.setRequestProperty("User-Agent", "Retro-AtariST/1.0 Android RetroMedia client");
        if (connection.getResponseCode() != 200) {
            throw new Exception("Game download returned HTTP " + connection.getResponseCode());
        }
        retroMediaDownloadBytes = 0;
        long contentLength = connection.getContentLengthLong();
        retroMediaDownloadTotal = contentLength > 0 ? contentLength : detail.optLong("totalBytes", 0);
        int written = 0;
        File first = null;
        try (InputStream raw = new FilterInputStream(connection.getInputStream()) {
            @Override
            public int read() throws java.io.IOException {
                int value = super.read();
                if (value >= 0) ++retroMediaDownloadBytes;
                return value;
            }

            @Override
            public int read(byte[] buffer, int offset, int length) throws java.io.IOException {
                int count = super.read(buffer, offset, length);
                if (count > 0) retroMediaDownloadBytes += count;
                return count;
            }
        }) {
            if (roms.length() == 1) {
                String name = safeFileName(roms.getJSONObject(0).optString("file", title));
                if (!supportedGame(name)) throw new Exception("Unsupported Atari ST image: " + name);
                first = writeGame(destination, name, raw);
                written = 1;
            } else {
                try (ZipInputStream zip = new ZipInputStream(raw)) {
                    ZipEntry entry;
                    while ((entry = zip.getNextEntry()) != null) {
                        if (entry.isDirectory() || !supportedGame(entry.getName())) continue;
                        File file = writeGame(destination, entry.getName(), zip);
                        if (first == null) first = file;
                        ++written;
                        zip.closeEntry();
                    }
                }
            }
        } finally {
            connection.disconnect();
        }
        if (written == 0) throw new Exception("Download contained no supported Atari ST images");
        downloadedPath = first == null ? "" : first.getAbsolutePath();
        publish("DOWNLOAD", fetchAccount(cookie), 1, written,
                title + " downloaded (" + written + " file" + (written == 1 ? "" : "s") + ")");
    }
}
