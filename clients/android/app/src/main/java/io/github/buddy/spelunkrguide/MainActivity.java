package io.github.buddy.spelunkrguide;

import android.app.Activity;
import android.app.UiModeManager;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.webkit.WebViewAssetLoader;

public final class MainActivity extends Activity {
    private static final String LOCAL_HOST = "appassets.androidplatform.net";
    private WebView web;
    private AudioManager audio;
    private AudioFocusRequest audioFocus;
    private boolean resumed;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        UiModeManager mode = (UiModeManager) getSystemService(UI_MODE_SERVICE);
        boolean television = mode != null && mode.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION;
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(28, 10, 87));
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        setContentView(root);
        if (television) getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        try {
            web = new WebView(this);
        } catch (RuntimeException missingWebView) {
            TextView message = new TextView(this);
            message.setText(R.string.missing_webview);
            message.setTextColor(Color.YELLOW);
            message.setPadding(40, 60, 40, 40);
            root.addView(message);
            return;
        }
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));
        web.setBackgroundColor(Color.rgb(28, 10, 87));
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSupportZoom(false);
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        WebViewAssetLoader assets = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this)).build();
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return assets.shouldInterceptRequest(request.getUrl());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("https".equals(uri.getScheme()) && LOCAL_HOST.equals(uri.getHost())) return false;
                if ("https".equals(uri.getScheme())) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); }
                    catch (ActivityNotFoundException ignored) { Toast.makeText(MainActivity.this, uri.toString(), Toast.LENGTH_LONG).show(); }
                }
                return true;
            }
        });
        web.requestFocus();
        web.loadUrl("https://" + LOCAL_HOST + "/assets/web/index.html?native=android" + (television ? "&tv=1" : ""));
        audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        audioFocus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setOnAudioFocusChangeListener(focus -> {
                    if (focus == AudioManager.AUDIOFOCUS_GAIN && resumed) call("resume");
                    else if (focus < 0) call("suspend");
                }).build();
        if (Build.VERSION.SDK_INT >= 33) getOnBackInvokedDispatcher().registerOnBackInvokedCallback(0, this::back);
    }

    private void call(String method) {
        if (web != null) web.evaluateJavascript("window.spelunkr && window.spelunkr." + method + "()", null);
    }

    private void action(String key) {
        if (web != null) web.evaluateJavascript("window.spelunkr && window.spelunkr.action('" + key + "')", null);
    }

    private void back() {
        if (web == null) { finish(); return; }
        web.evaluateJavascript("window.spelunkr ? window.spelunkr.handleBack() : false",
                handled -> { if (!"true".equals(handled)) finish(); });
    }

    @Override public void onBackPressed() { back(); }

    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        String key;
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_DPAD_UP: case KeyEvent.KEYCODE_CHANNEL_UP: key = "up"; break;
            case KeyEvent.KEYCODE_DPAD_DOWN: case KeyEvent.KEYCODE_CHANNEL_DOWN: key = "down"; break;
            case KeyEvent.KEYCODE_DPAD_LEFT: key = "left"; break;
            case KeyEvent.KEYCODE_DPAD_RIGHT: key = "right"; break;
            case KeyEvent.KEYCODE_DPAD_CENTER: case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_MEDIA_PLAY: case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: key = "ok"; break;
            case KeyEvent.KEYCODE_MENU: case KeyEvent.KEYCODE_INFO: key = "help"; break;
            default: return super.dispatchKeyEvent(event);
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN) action(key);
        return true;
    }

    @Override protected void onResume() {
        super.onResume();
        resumed = true;
        if (web != null) { web.onResume(); call("resume"); }
        if (audio != null && audioFocus != null) audio.requestAudioFocus(audioFocus);
    }

    @Override protected void onPause() {
        resumed = false;
        call("suspend");
        if (web != null) web.onPause();
        if (audio != null && audioFocus != null) audio.abandonAudioFocusRequest(audioFocus);
        super.onPause();
    }

    @Override protected void onDestroy() {
        if (web != null) { web.stopLoading(); web.destroy(); web = null; }
        super.onDestroy();
    }
}
