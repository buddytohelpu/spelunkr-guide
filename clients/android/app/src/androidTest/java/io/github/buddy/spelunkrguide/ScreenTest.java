package io.github.buddy.spelunkrguide;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.pm.ActivityInfo;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.webkit.WebView;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.filters.SdkSuppress;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Checks the real WebView, native fullscreen bridge, rotation and Android Back. */
@RunWith(AndroidJUnit4.class)
@SdkSuppress(minSdkVersion = 30)
public class ScreenTest {
    private MainActivity activity;
    private WebView web;

    private WebView findWeb(View view) {
        if (view instanceof WebView) return (WebView) view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                WebView found = findWeb(group.getChildAt(i));
                if (found != null) return found;
            }
        }
        return null;
    }

    private String evaluate(String source) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<String> result = new AtomicReference<>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() ->
                web.evaluateJavascript(source, value -> { result.set(value); done.countDown(); }));
        assertTrue("WebView did not evaluate JavaScript", done.await(10, TimeUnit.SECONDS));
        return result.get();
    }

    private void waitFor(String condition) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 30000;
        String last = "";
        while (SystemClock.elapsedRealtime() < deadline) {
            last = evaluate(condition);
            if ("true".equals(last)) return;
            SystemClock.sleep(150);
        }
        throw new AssertionError("Timed out: " + condition + "; last value: " + last);
    }

    private boolean barsVisible() {
        AtomicReference<Boolean> visible = new AtomicReference<>(true);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            WindowInsets insets = activity.getWindow().getDecorView().getRootWindowInsets();
            visible.set(insets == null || insets.isVisible(WindowInsets.Type.statusBars())
                    || insets.isVisible(WindowInsets.Type.navigationBars()));
        });
        return visible.get();
    }

    private void waitForBars(boolean visible) {
        long deadline = SystemClock.elapsedRealtime() + 10000;
        while (SystemClock.elapsedRealtime() < deadline) {
            if (barsVisible() == visible) return;
            SystemClock.sleep(150);
        }
        assertEquals("System bars did not follow watch/guide mode", visible, barsVisible());
    }

    private void attach(ActivityScenario<MainActivity> scenario) throws Exception {
        scenario.onActivity(current -> { activity = current; web = findWeb(current.getWindow().getDecorView()); });
        assertTrue("WebView is missing", web != null);
        waitFor("!!window.spelunkr && !!window.SpelunkrNative");
    }

    private void assertGuideFits() throws Exception {
        waitFor("(() => { const credits=document.querySelector('.network-note').getBoundingClientRect();"
                + "const guide=document.getElementById('guide-viewport').getBoundingClientRect();"
                + "return document.documentElement.scrollWidth<=innerWidth+1 && credits.bottom<=innerHeight+1 && guide.height>30; })()");
    }

    private void watchAndReturn() throws Exception {
        // Expand is available while schedules load, so this regression check needs no network.
        evaluate("document.getElementById('expand-button').click()");
        waitFor("document.getElementById('television').classList.contains('watch-mode')");
        waitForBars(false);
        waitFor("(() => { const r=document.getElementById('video').getBoundingClientRect();"
                + "return Math.abs(r.width-innerWidth)<2 && Math.abs(r.height-innerHeight)<2 && r.height>0; })()");
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);
        waitFor("!document.getElementById('television').classList.contains('watch-mode')");
        waitForBars(true);
        assertGuideFits();
    }

    @Test public void phoneGuideFullscreenBackAndRotation() throws Exception {
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            attach(scenario);
            assertGuideFits();
            watchAndReturn();
            scenario.onActivity(current -> current.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));
            waitFor("innerWidth>innerHeight");
            assertGuideFits();
            watchAndReturn();
        }
    }

    @Test public void pictureChoiceSurvivesActivityRecreation() throws Exception {
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            attach(scenario);
            evaluate("localStorage.removeItem('spelunkr-picture'); location.reload()");
            waitFor("!!window.spelunkr && document.documentElement.dataset.picture==='original'");
            evaluate("document.getElementById('aspect-button').click()");
            assertEquals("\"fill\"", evaluate("getComputedStyle(document.getElementById('video')).objectFit"));
            scenario.recreate();
            attach(scenario);
            assertEquals("\"stretch\"", evaluate("document.documentElement.dataset.picture"));
            evaluate("document.getElementById('aspect-button').click()");
            assertEquals("\"contain\"", evaluate("getComputedStyle(document.getElementById('video')).objectFit"));
        }
    }
}
