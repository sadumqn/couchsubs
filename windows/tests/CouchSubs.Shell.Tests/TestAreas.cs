// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Shell.Tests;

/// <summary>Testlerde ek alan kurmak için kısa yol: kimliği sırasıyla "area1", "area2" …</summary>
internal static class TestAreas
{
    public static UserSettings WithArea(this UserSettings settings, CropRegion region, bool live = false, ResultTarget target = ResultTarget.Tv) =>
        settings.WithAddedExtraArea(new ExtraArea($"area{settings.ExtraAreas.Count + 1}", "", region, live, target));
}
