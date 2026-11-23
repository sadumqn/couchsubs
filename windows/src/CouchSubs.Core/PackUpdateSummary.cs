// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// "Paketleri şimdi güncelle"nin sonucu: hangi paket eklendi, hangisi güncellendi, kaç satır geldi. Güncellemeden önceki
/// kitaplık ile yenilemede inen paketlerin yeni satır sayısı karşılaştırılır. Mac ve iPhone'daki
/// CouchSubsCore/PackUpdateSummary.swift ve Android'deki packs/PackUpdateSummary.kt ile aynı kurallar.
/// </summary>
public sealed class PackUpdateSummary
{
    /// <param name="Added">Önceden bu bilgisayarda yoktu (ne uygulamayla geldi ne indirilmişti).</param>
    /// <param name="Lines">Paketin şimdiki satır sayısı.</param>
    /// <param name="LineDelta">Önceki sürüme göre satır farkı (eklenen pakette bütün satırlar).</param>
    public sealed record Change(string Id, string Title, bool Added, int Lines, int LineDelta);

    /// <summary>Yenilemede inen bir paket (başlığı ve satır sayısı).</summary>
    public sealed record Downloaded(string Id, string Title, int Lines);

    /// <summary>İnen paketler, inme sırasıyla.</summary>
    public IReadOnlyList<Change> Changes { get; }

    /// <param name="before">Güncellemeden önceki paketler (aynı kimlik birden çok kez varsa son gelen geçerli).</param>
    /// <param name="downloaded">Yenilemede inenler. Aynı kimlik bir kez sayılır.</param>
    public PackUpdateSummary(IEnumerable<(string Id, int Lines)> before, IEnumerable<Downloaded> downloaded)
    {
        var previous = new Dictionary<string, int>();
        foreach (var (id, lines) in before) previous[id] = lines;
        var seen = new HashSet<string>();
        var changes = new List<Change>();
        foreach (var pack in downloaded)
        {
            if (!seen.Add(pack.Id)) continue;
            var known = previous.TryGetValue(pack.Id, out var old);
            changes.Add(new Change(pack.Id, pack.Title, !known, pack.Lines, pack.Lines - (known ? old : 0)));
        }
        Changes = changes;
    }

    public bool IsEmpty => Changes.Count == 0;
    public IReadOnlyList<Change> Updated => [.. Changes.Where(change => !change.Added)];
    public IReadOnlyList<Change> Added => [.. Changes.Where(change => change.Added)];

    /// <summary>Gelen yeni satırların toplamı (eklenen paketlerin bütün satırları ve güncellenenlerdeki artış; azalan sayılmaz).</summary>
    public int NewLines => Changes.Sum(change => Math.Max(0, change.LineDelta));

    /// <summary>"2 paket güncellendi: Grand Theft Auto VI (+12.300 satır), Red Dead Redemption 2 (+800 satır)."</summary>
    public string Describe(Localizer text)
    {
        var parts = new List<string>();
        var updated = Updated;
        var added = Added;
        if (updated.Count > 0)
        {
            var list = string.Join(", ", updated.Select(change => UpdatedItem(text, change)));
            parts.Add(updated.Count == 1 ? text.Format("1 pack updated: %@.", list) : text.Format("%lld packs updated: %@.", updated.Count, list));
        }
        if (added.Count > 0)
        {
            var list = string.Join(", ", added.Select(change => text.Format("%1$@ (%2$@ lines)", change.Title, change.Lines.ToString("N0"))));
            parts.Add(added.Count == 1 ? text.Format("1 pack added: %@.", list) : text.Format("%lld packs added: %@.", added.Count, list));
        }
        if (NewLines > 0) parts.Add(text.Format("%@ new lines in total.", NewLines.ToString("N0")));
        return string.Join("\n", parts);
    }

    private static string UpdatedItem(Localizer text, Change change) => change.LineDelta switch
    {
        > 0 => text.Format("%1$@ (+%2$@ lines)", change.Title, change.LineDelta.ToString("N0")),
        < 0 => text.Format("%1$@ (%2$@ fewer lines)", change.Title, (-change.LineDelta).ToString("N0")),
        _ => text.Format("%@ (translations revised)", change.Title),
    };
}

/// <summary>Elle güncellemenin sonucu (Ayarlar'da ileti olarak gösterilir).</summary>
public sealed record PackUpdateOutcome(PackUpdateOutcome.Kind Result, PackUpdateSummary Summary, string? Reason = null)
{
    public enum Kind { UpToDate, Updated, Failed }

    public string Title(Localizer text) => Result switch
    {
        Kind.UpToDate => text["Packs are up to date"],
        Kind.Updated => text["Packs updated"],
        _ => text["The packs could not be updated"],
    };

    /// <summary>Hatada neden, "bu bilgisayardaki paketler kullanılmaya devam ediyor" ve (varsa) hataya rağmen inenler.</summary>
    public string Message(Localizer text) => Result switch
    {
        Kind.UpToDate => text["The packs are already up to date."],
        Kind.Updated => Summary.Describe(text),
        _ => string.Join("\n\n", new[] { Reason ?? "", text["The packs on this computer are still used."] }
            .Concat(Summary.IsEmpty ? [] : [Summary.Describe(text)]).Where(part => part.Length > 0)),
    };
}
