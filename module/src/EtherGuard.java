package local.etherguard;

import java.lang.reflect.*;
import java.util.concurrent.Executor;

/** No raw Binder transaction numbers, settings changes or USB operations. */
public final class EtherGuard {
    public static void main(String[] args) {
        try {
            if (args.length != 1 || !(args[0].equals("probe") || args[0].equals("start")))
                throw new IllegalArgumentException("probe|start only");
            Class<?> looper = Class.forName("android.os.Looper");
            looper.getMethod("prepareMainLooper").invoke(null);
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object thread = at.getMethod("systemMain").invoke(null);
            Object context = at.getMethod("getSystemContext").invoke(thread);
            Class<?> ctx = Class.forName("android.content.Context");
            // Use system context; privileged root caller is checked by the native service.
            Object manager = ctx.getMethod("getSystemService", String.class)
                .invoke(context, "tethering");
            if (manager == null) throw new IllegalStateException("tethering service unavailable");
            Class<?> tm = Class.forName("android.net.TetheringManager");
            int ethernet = tm.getField("TETHERING_ETHERNET").getInt(null);
            if (ethernet != 5) throw new IllegalStateException("unexpected Ethernet type");
            Class<?> callback = Class.forName("android.net.TetheringManager$StartTetheringCallback");
            if (!callback.isInterface()) throw new IllegalStateException("unsupported callback ABI");
            Method start = tm.getMethod("startTethering", int.class, Executor.class, callback);
            if (args[0].equals("probe")) {
                System.out.println("PROBE_OK ethernet=5 method=" + start);
                System.exit(0);
            }
            Object cb = Proxy.newProxyInstance(callback.getClassLoader(), new Class<?>[]{callback},
                (proxy, method, values) -> {
                    String name = method.getName();
                    if (name.equals("onTetheringStarted")) {
                        System.out.println("START_ACCEPTED"); System.exit(0);
                    }
                    if (name.equals("onTetheringFailed")) {
                        System.out.println("START_FAILED error=" + values[0]); System.exit(3);
                    }
                    if (name.equals("toString")) return "EtherGuardCallback";
                    if (name.equals("hashCode")) return System.identityHashCode(proxy);
                    if (name.equals("equals")) return proxy == values[0];
                    return null;
                });
            Executor direct = runnable -> runnable.run();
            start.invoke(manager, ethernet, direct, cb);
            looper.getMethod("loop").invoke(null);
        } catch (Throwable error) {
            if (error instanceof InvocationTargetException)
                error = ((InvocationTargetException)error).getTargetException();
            error.printStackTrace(System.out);
            System.exit(2);
        }
    }
}
