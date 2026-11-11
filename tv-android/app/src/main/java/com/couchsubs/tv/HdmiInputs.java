// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.content.Context;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** TV'nin HDMI girişleri; uygulama içi mod ve katman modu ortak kullanır. */
final class HdmiInputs {
    private HdmiInputs() {}

    /**
     * TV'nin HDMI girişleri, port numarasına göre sıralı. Girişin numarası sıradaki yeridir.
     * HDMI-CEC ile bağlı cihazlar (PS5 gibi) bazı TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar sayılmaz,
     * yoksa numaralar kayar ve iki bağlı giriş görünür. Kimlikler sayısal sıralanır ("HW10", "HW2"den sonra gelir).
     */
    static List<TvInputInfo> list(Context context) {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = manager(context);
        if (manager == null) return inputs;
        for (TvInputInfo input : manager.getTvInputList()) {
            if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput() && input.getParentId() == null) {
                inputs.add(input);
            }
        }
        Collections.sort(inputs, Comparator.comparingLong((TvInputInfo input) -> lastNumber(input.getId()))
                .thenComparing(TvInputInfo::getId));
        return inputs;
    }

    /** 1'den başlayan numaraya karşılık gelen HDMI girişinin kimliği, yoksa null. */
    static String idForPort(Context context, int port) {
        List<TvInputInfo> inputs = list(context);
        return port >= 1 && port <= inputs.size() ? inputs.get(port - 1).getId() : null;
    }

    /** Tek bağlı HDMI girişi varsa onun numarası, yoksa 0. */
    static int consolePort(Context context) {
        TvInputManager manager = manager(context);
        if (manager == null) return 0;
        List<TvInputInfo> inputs = list(context);
        int found = 0;
        for (int i = 0; i < inputs.size(); i++) {
            if (manager.getInputState(inputs.get(i).getId()) != TvInputManager.INPUT_STATE_CONNECTED) continue;
            if (found != 0) return 0;
            found = i + 1;
        }
        return found;
    }

    /** Girişte bir cihaz var mı; TV bunu bildirmiyorsa var sayılır. */
    static boolean hasSource(Context context, String id) {
        TvInputManager manager = manager(context);
        if (manager == null || id == null) return true;
        try {
            return manager.getInputState(id) != TvInputManager.INPUT_STATE_DISCONNECTED;
        } catch (RuntimeException e) {
            return true;
        }
    }

    private static TvInputManager manager(Context context) {
        return (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
    }

    /** Kimliğin sonundaki sayı ("…/HW15" → 15); yoksa en sona konur. */
    static long lastNumber(String id) {
        int end = id.length();
        while (end > 0 && !Character.isDigit(id.charAt(end - 1))) end--;
        int start = end;
        while (start > 0 && Character.isDigit(id.charAt(start - 1))) start--;
        if (start == end) return Long.MAX_VALUE;
        try { return Long.parseLong(id.substring(start, end)); } catch (NumberFormatException e) { return Long.MAX_VALUE; }
    }
}
