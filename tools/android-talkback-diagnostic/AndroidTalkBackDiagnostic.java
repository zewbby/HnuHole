import android.app.UiAutomation;
import android.graphics.Rect;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

/** Shell-only, bounded diagnostics. Never clicks, changes settings, or emits arbitrary UI text. */
public final class AndroidTalkBackDiagnostic {
  private static final String PACKAGE = "org.hnuhole.hnuhole_mobile";
  private static final String ERROR = "密码复验失败，请重新输入密码。";
  private static final String[][] PUBLIC_LABELS = {
      {"password_error", ERROR}, {"confirmation", "新恢复码完整确认"},
      {"confirm", "确认并激活新恢复码"},
      {"unknown", "提交结果尚未确定"}, {"query", "核对原结果"},
      {"committed", "变更已确认提交"}, {"ack", "返回当前凭据"},
      {"rotate", "轮换恢复码"}, {"hide", "我已保存，隐藏原码并确认"}
  };
  private static final int KEEP_ACCESSIBILITY_SERVICES = 1;
  private static final AtomicInteger focusedEvents = new AtomicInteger();
  private static final AtomicInteger publicFocusedEvents = new AtomicInteger();
  private static final AtomicInteger publicHoverEvents = new AtomicInteger();
  private static final AtomicInteger unresolvedSources = new AtomicInteger();
  private static String stage = "arguments";

  private static synchronized void emit(JSONObject value) {
    System.out.println(value.toString());
    System.out.flush();
  }

  private static JSONObject record(String type) throws Exception {
    return new JSONObject().put("record", type).put("diagnosticOnly", true)
        .put("humanAction", false).put("countsAsNiU03Acceptance", false)
        .put("speechCaptured", false).put("arbitraryUiTextEmitted", false);
  }

  private static boolean owned(AccessibilityNodeInfo node) {
    return node != null && PACKAGE.contentEquals(node.getPackageName() == null
        ? "" : node.getPackageName());
  }

  private static boolean publicError(AccessibilityNodeInfo node) {
    if (!owned(node) || node.isPassword()) return false;
    return ERROR.contentEquals(node.getText() == null ? "" : node.getText())
        || ERROR.contentEquals(node.getContentDescription() == null
            ? "" : node.getContentDescription());
  }

  private static List<String> publicTargets(AccessibilityNodeInfo node) {
    List<String> targets = new ArrayList<>();
    if (!owned(node)) return targets;
    // Do not inspect password text/value; the public field name is in hint/description.
    String text = node.isPassword() || node.getText() == null ? "" : node.getText().toString();
    String description = node.getContentDescription() == null ? "" : node.getContentDescription().toString();
    String hint = node.getHintText() == null ? "" : node.getHintText().toString();
    for (String[] label : PUBLIC_LABELS) {
      if (text.contains(label[1]) || description.contains(label[1]) || hint.contains(label[1])) {
        targets.add(label[0]);
      }
    }
    return targets;
  }

  private static JSONObject nodeSummary(AccessibilityNodeInfo node) throws Exception {
    Rect bounds = new Rect();
    node.getBoundsInScreen(bounds);
    List<String> targets = publicTargets(node);
    JSONObject properties = new JSONObject();
    for (String[] label : PUBLIC_LABELS) {
      if (!targets.contains(label[0])) continue;
      properties.put(label[0], new JSONObject()
          .put("textMatches", !node.isPassword() && node.getText() != null
              && node.getText().toString().contains(label[1]))
          .put("descriptionMatches", node.getContentDescription() != null
              && node.getContentDescription().toString().contains(label[1]))
          .put("hintMatches", node.getHintText() != null && node.getHintText().toString().contains(label[1])));
    }
    JSONObject value = new JSONObject().put("publicTargets", new JSONArray(targets))
        .put("matchingProperties", properties)
        .put("bounds", new JSONArray(new int[]{bounds.left, bounds.top, bounds.right, bounds.bottom}))
        .put("focusable", node.isFocusable()).put("enabled", node.isEnabled())
        .put("visibleToUser", node.isVisibleToUser()).put("clickable", node.isClickable())
        .put("password", node.isPassword()).put("accessibilityFocused", node.isAccessibilityFocused())
        .put("supportsAccessibilityFocus", (node.getActions()
            & AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS) != 0);
    // IDs only; failure of this optional reflection never changes hidden-api policy.
    try {
      long id = ((Long) AccessibilityNodeInfo.class.getMethod("getSourceNodeId").invoke(node));
      value.put("sourceNodeId", Long.toString(id)).put("virtualNodeId", (int) (id >> 32));
    } catch (ReflectiveOperationException ignored) {
      value.put("sourceNodeIdAvailable", false);
    }
    return value;
  }

  private static void requirePid(String expected) throws Exception {
    Process process = new ProcessBuilder("/system/bin/pidof", PACKAGE).start();
    String actual;
    try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream(), "UTF-8"))) {
      actual = reader.readLine();
    }
    if (process.waitFor() != 0 || actual == null || !expected.equals(actual.trim())) {
      throw new IllegalStateException("OWNED_APP_PID_CHANGED");
    }
  }

  private static void collect(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> matches,
      boolean includeKnownPublicTargets,
      int depth, AtomicInteger visited) throws Exception {
    if (node == null) return;
    if (depth > 64 || visited.incrementAndGet() > 2048) {
      throw new IllegalStateException("BOUNDED_TREE_LIMIT");
    }
    if (includeKnownPublicTargets ? !publicTargets(node).isEmpty() : publicError(node)) {
      matches.add(AccessibilityNodeInfo.obtain(node));
    }
    for (int index = 0; index < node.getChildCount(); index++) {
      AccessibilityNodeInfo child = node.getChild(index);
      if (child == null) continue;
      try { collect(child, matches, includeKnownPublicTargets, depth + 1, visited); }
      finally { child.recycle(); }
    }
  }

  private static JSONObject currentFocus(UiAutomation automation) throws Exception {
    AccessibilityNodeInfo node = automation.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY);
    try {
      JSONObject result = new JSONObject().put("available", node != null)
          .put("matchesPublicError", publicError(node))
          .put("publicTargets", new JSONArray(publicTargets(node)));
      if (!publicTargets(node).isEmpty()) result.put("node", nodeSummary(node));
      return result;
    } finally { if (node != null) node.recycle(); }
  }

  public static void main(String[] arguments) throws Exception {
    HandlerThread thread = null;
    UiAutomation automation = null;
    boolean connected = false;
    int exitCode = 0;
    List<AccessibilityNodeInfo> matches = new ArrayList<>();
    try {
      emit(record("stage").put("stage", "entered_main")
          .put("shellDiagnosticPid", android.os.Process.myPid()));
      // This shell process has no ActivityThread. The OEM accessibility client
      // constructs main-looper Handlers, so initialize the ordinary public Looper.
      if (Looper.getMainLooper() == null) Looper.prepareMainLooper();
      if (arguments.length != 3 || !(arguments[0].equals("inspect")
          || arguments[0].equals("inspect-public") || arguments[0].equals("focus-error"))
          || !arguments[1].matches("[1-9][0-9]{1,6}")) {
        throw new IllegalArgumentException("FIXED_DIAGNOSTIC_ARGUMENTS_REQUIRED");
      }
      int seconds = Integer.parseInt(arguments[2]);
      if (seconds < 0 || seconds > 10 || android.os.Process.myUid() != 2000) {
        throw new IllegalArgumentException("BOUNDED_SHELL_DIAGNOSTIC_REQUIRED");
      }
      String expectedPid = arguments[1];
      stage = "owned_pid";
      requirePid(expectedPid);
      thread = new HandlerThread("hnuhole-public-a11y-diagnostic");
      thread.start();
      stage = "construct_connection";
      emit(record("stage").put("stage", stage));
      Object connection = Class.forName("android.app.UiAutomationConnection")
          .getDeclaredConstructor().newInstance();
      Class<?> connectionInterface = Class.forName("android.app.IUiAutomationConnection");
      stage = "construct_automation";
      emit(record("stage").put("stage", stage));
      Constructor<?> constructor = UiAutomation.class.getConstructor(Looper.class, connectionInterface);
      automation = (UiAutomation) constructor.newInstance(thread.getLooper(), connection);
      stage = "connect_keep_services";
      emit(record("stage").put("stage", stage));
      UiAutomation.class.getMethod("connect", int.class)
          .invoke(automation, KEEP_ACCESSIBILITY_SERVICES);
      connected = true;
      stage = "verify_actual_connection_flags";
      int flags = ((Integer) UiAutomation.class.getMethod("getFlags").invoke(automation));
      if (flags != KEEP_ACCESSIBILITY_SERVICES) throw new IllegalStateException("UNSAFE_CONNECTION_FLAGS");
      emit(record("connected").put("actualConnectionFlags", flags)
          .put("dontSuppressAccessibilityServices", true).put("ownedAppPid", Integer.parseInt(expectedPid)));

      automation.setOnAccessibilityEventListener(new UiAutomation.OnAccessibilityEventListener() {
        @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        int type = event.getEventType();
        if (type != AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED
            && type != AccessibilityEvent.TYPE_VIEW_HOVER_ENTER) return;
        if (type == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) focusedEvents.incrementAndGet();
        AccessibilityNodeInfo source = event.getSource();
        try {
          if (source == null) unresolvedSources.incrementAndGet();
          if (!publicTargets(source).isEmpty()) {
            if (publicError(source)) {
              if (type == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) publicFocusedEvents.incrementAndGet();
              else publicHoverEvents.incrementAndGet();
            }
            emit(record("public_event").put("type", type)
                .put("event", type == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED
                    ? "TYPE_VIEW_ACCESSIBILITY_FOCUSED" : "TYPE_VIEW_HOVER_ENTER")
                .put("node", nodeSummary(source)));
          }
        } catch (Exception ignored) {
          unresolvedSources.incrementAndGet();
        } finally { if (source != null) source.recycle(); }
        }
      });

      stage = "active_window_public_error";
      AccessibilityNodeInfo root = automation.getRootInActiveWindow();
      try {
        if (!owned(root)) throw new IllegalStateException("OWNED_APP_NOT_ACTIVE_WINDOW");
        collect(root, matches, arguments[0].equals("inspect-public"), 0, new AtomicInteger());
      } finally { if (root != null) root.recycle(); }
      requirePid(expectedPid);
      if (arguments[0].equals("inspect-public")) {
        JSONArray summaries = new JSONArray();
        for (AccessibilityNodeInfo node : matches) summaries.put(nodeSummary(node));
        emit(record("known_public_nodes").put("matchingNodeCount", matches.size()).put("nodes", summaries));
        emit(record("focus_before").put("accessibilityFocus", currentFocus(automation)));
        SystemClock.sleep(seconds * 1000L);
        requirePid(expectedPid);
        emit(record("focus_after").put("accessibilityFocus", currentFocus(automation))
            .put("rawFocusedEventCount", focusedEvents.get())
            .put("publicErrorFocusedEventCount", publicFocusedEvents.get())
            .put("publicErrorHoverEventCount", publicHoverEvents.get())
            .put("unresolvedEventSourceCount", unresolvedSources.get()));
      } else {
      JSONObject found = record("public_error_node").put("matchingNodeCount", matches.size());
      if (matches.size() == 1) found.put("node", nodeSummary(matches.get(0)));
      emit(found);
      if (matches.size() != 1) throw new IllegalStateException("UNIQUE_PUBLIC_ERROR_REQUIRED");
      AccessibilityNodeInfo error = matches.get(0);
      if (!error.isFocusable() || !error.isEnabled() || !error.isVisibleToUser()
          || error.isClickable() || error.isPassword()) {
        throw new IllegalStateException("PUBLIC_ERROR_NOT_SAFE_FOCUS_TARGET");
      }
      emit(record("focus_before").put("accessibilityFocus", currentFocus(automation)));
      if (arguments[0].equals("focus-error")) {
        stage = "diagnostic_public_error_focus";
        requirePid(expectedPid);
        boolean accepted = error.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
        emit(record("focus_request").put("action", "ACTION_ACCESSIBILITY_FOCUS")
            .put("actionAccepted", accepted));
      }
      stage = "bounded_observation";
      long end = SystemClock.elapsedRealtime() + seconds * 1000L;
      while (SystemClock.elapsedRealtime() < end) {
        requirePid(expectedPid);
        SystemClock.sleep(100);
      }
      requirePid(expectedPid);
      emit(record("focus_after").put("accessibilityFocus", currentFocus(automation))
          .put("rawFocusedEventCount", focusedEvents.get())
          .put("publicErrorFocusedEventCount", publicFocusedEvents.get())
          .put("publicErrorHoverEventCount", publicHoverEvents.get())
          .put("unresolvedEventSourceCount", unresolvedSources.get()));
      }
    } catch (Throwable error) {
      Throwable cause = error instanceof InvocationTargetException
          ? ((InvocationTargetException) error).getCause() : error;
      emit(record("error").put("stage", stage).put("exceptionClass", cause.getClass().getName())
          .put("reflectionPolicyChanged", false));
      exitCode = 2;
    } finally {
      for (AccessibilityNodeInfo node : matches) node.recycle();
      boolean disconnected = !connected;
      if (automation != null && connected) {
        try {
          automation.setOnAccessibilityEventListener(null);
          Method disconnect = UiAutomation.class.getMethod("disconnect");
          disconnect.invoke(automation);
          disconnected = true;
        } catch (ReflectiveOperationException error) { exitCode = 3; }
      }
      if (thread != null) thread.quitSafely();
      emit(record("disconnected").put("disconnected", disconnected));
    }
    System.exit(exitCode);
  }
}
