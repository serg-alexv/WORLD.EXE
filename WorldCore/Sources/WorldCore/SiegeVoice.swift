import Foundation

/// Presentation policy only. Never mutates a mission, score, sensor archive or telemetry.
public enum SiegeHumor: String, Codable, CaseIterable, Sendable {
    case off, sarcastic, black
    public static func restored(_ raw: String) -> Self { Self(rawValue: raw) ?? .off }
    public var title: String {
        switch self { case .off: return "Без шуток"; case .sarcastic: return "Сарказм"; case .black: return "Чёрный" }
    }
    fileprivate var instruction: String {
        switch self {
        case .off: return "Neutral, concise mission commentary. No jokes, mockery or death metaphors."
        case .sarcastic: return "Dry sarcasm and post-irony about fictional corporate bureaucracy. One understated punchline."
        case .black: return "Bleak, sharp gallows humor and post-irony about fictional expendable space crews, corporate cost cutting and absurd paperwork. One deadpan punchline, not a motivational speech."
        }
    }
}
public enum SiegeVoiceEvent: String, CaseIterable, Sendable {
    case deployment, move, pulse, brace, endTurn, damaged, sentryDown, relay, victory, defeat, replay, rejected
    case rankingEmpty, rankingSaved, rankingCleared
}

public enum SiegeVoice {
    /// Explicit, bounded catalogue. Variant selection is deterministic across devices and launches.
    public static func line(_ event: SiegeVoiceEvent, tone: SiegeHumor, variant: UInt64 = 0) -> String {
        if tone == .off { return neutral(event) }
        let options = lines(event, black: tone == .black)
        return options[Int(variant % UInt64(options.count))]
    }
    private static func neutral(_ event: SiegeVoiceEvent) -> String {
        switch event {
        case .deployment: return "Заберите сигнал у ретранслятора R и доставьте его к точке E."
        case .move: return "Позиция изменена. Проверьте очки действий и прогноз угрозы."
        case .pulse: return "Импульс выполнен. Урон определён игровыми правилами."
        case .brace: return "Защита подготовлена на следующий ход противника."
        case .endTurn: return "Ход завершён. Проверьте патруль и опасный ряд."
        case .damaged: return "Получен игровой урон. Проверьте запас здоровья."
        case .sentryDown: return "Часовой отключён. Опасность рядов остаётся активной."
        case .relay: return "Сигнал получен. Вернитесь к E и выполните извлечение."
        case .victory: return "Сигнал доставлен. Миссия завершена победой."
        case .defeat: return "Миссия проиграна. Повтор создаёт новый игровой сеанс."
        case .replay: return "Создан новый сеанс с выбранными seed и сложностью."
        case .rejected: return "Действие не выполнено. Причина указана в сообщении игры."
        case .rankingEmpty: return "Для этих seed и сложности ещё нет завершённых побед."
        case .rankingSaved: return "Победа записана в локальный рейтинг устройства."
        case .rankingCleared: return "Локальный рейтинг очищен. Миссия не изменена."
        }
    }
    private static func lines(_ event: SiegeVoiceEvent, black: Bool) -> [String] {
        switch event {
        case .deployment:
            return black ? ["Бюджет на эвакуацию утверждён. Эвакуируем бюджет.", "Вы не расходный материал. У материала есть складской номер.", "Контракт бессрочный. Срок исполнителя обсуждается отдельно."]
                : ["Всё идёт по плану. План нам пока не выдали.", "Начальство верит в вас. Это дешевле подкрепления."]
        case .move:
            return black ? ["Каждый шаг приближает нас к цели. Юристы запретили уточнять, к какой.", "Хорошая позиция. Для заключительного отчёта особенно."]
                : ["Тактическое перемещение. Раньше это называлось «пойти туда».", "Маршрут согласован с отделом, который никогда здесь не был."]
        case .pulse:
            return black ? ["Переговоры перешли в фазу списания оборудования.", "Дипломатия закончилась. Началась амортизация."]
                : ["Аргумент принят. Оппонент дымится от восторга.", "Провели короткую презентацию. Без слайдов, зато с импульсом."]
        case .brace:
            return black ? ["Укрытие сертифицировано отделом, которого больше нет.", "Пригнитесь. В отчёте вы нужны хотя бы одной строкой."]
                : ["Занять укрытие — единственный пункт инструкции, написанный не юристом.", "Поздравляю: стена впервые работает на вас."]
        case .endTurn:
            return black ? ["Ход противника. HR просит не менять число сотрудников до конца квартала.", "Инициатива у врага. У нас — форма для посмертной обратной связи."]
                : ["Передаём инициативу. Руководство называет это делегированием.", "Теперь противник покажет, как он понял наше техническое задание."]
        case .damaged:
            return black ? ["Страховка покрывает ущерб оборудованию. Отойдите от оборудования.", "Медотдел рекомендует не усугублять статистику. Медотдел сокращён."]
                : ["Это не провал. Это платная обратная связь.", "Проверили гипотезу о собственной неуязвимости. Не прошла рецензию."]
        case .sentryDown:
            return black ? ["Противник переведён на бессрочную удалёнку.", "Часовой списан. Наконец-то взаимопонимание с бухгалтерией."]
                : ["Техническая поддержка противника больше не отвечает.", "Убедительный аргумент. Обжалованию не подлежит."]
        case .relay:
            return black ? ["Сигнал важнее экипажа. Просто у сигнала лучше договор.", "Посылка получена. Теперь доставим её вместе с остатками курьера."]
                : ["Сигнал наш. Осталось победить самовывоз.", "Цель получена. Не забудьте себя: вас нет в списке комплектующих."]
        case .victory:
            return black ? ["Экипаж вернулся живым. Бухгалтерия пересчитывает ущерб.", "Вы выжили. Это нарушение сметы, но приятное.", "Операция завершена. Награда — право явиться на следующую."]
                : ["Миссия выполнена. Начальство всегда знало, что так и будет.", "Отличная работа. В отчёте её припишут стратегии."]
        case .defeat:
            return black ? ["Чёрный ящик цел. Остальной коллектив — предмет дискуссии.", "Повторить миссию? Отдел кадров уже размораживает аргументы.", "Вакансия снова открыта. Требование к опыту снято."]
                : ["Не поражение, а ранняя версия победы. Очень ранняя.", "Сценарий повторяемый. Ошибки — по желанию."]
        case .replay:
            return black ? ["Новый экипаж. Старые корпоративные ценности.", "Ваш предшественник оставил ценный опыт. Забрать не успел."]
                : ["Снова тот же план. Теперь с премиальным предчувствием.", "Повтор — мать обучения. И квартальной отчётности."]
        case .rejected:
            return black ? ["Даже этот контракт не разрешает всё. Прочтите причину отказа.", "Безрассудство принято к сведению, но не к исполнению."]
                : ["Правила прочитали ваше предложение. И остались правилами.", "Заявка отклонена. На этот раз не бюрократией, а геометрией."]
        case .rankingEmpty:
            return black ? ["Мемориальная доска пуста. Здесь пока учитывают только вернувшихся.", "Список лучших пуст. Отдел кадров называет это возможностью роста."]
                : ["Конкуренция пока идеальная: конкурентов нет.", "Рейтинг ждёт побед. Намёк достаточно прозрачный."]
        case .rankingSaved:
            return black ? ["Имя сохранено на этом устройстве. Корпоративное бессмертие — без резервной планеты.", "Вы вошли в список лучших. Список выживших оказался короче."]
                : ["Местный рекорд. Галактика пока не уведомлена.", "Таблица обновлена. Самооценка — вручную."]
        case .rankingCleared:
            return black ? ["Доска почёта очищена. Экипажу обещали, что это только интерфейс.", "История успеха удалена. Для истории расходов нужна отдельная лицензия."]
                : ["Начинаем с чистого рейтинга. Прошлое побеждено кнопкой.", "Статистика улучшена устранением статистики."]
        }
    }
    public static func event(before: SignalSiege, after: SignalSiege, command: SiegeCommand) -> SiegeVoiceEvent {
        if after.phase == .victory { return .victory }
        if after.phase == .defeat { return .defeat }
        if after.health < before.health { return .damaged }
        if before.sentryHealth > 0 && after.sentryHealth == 0 { return .sentryDown }
        switch command {
        case .move: return .move
        case .pulse: return .pulse
        case .brace: return .brace
        case .secureRelay: return .relay
        case .extract: return .victory
        case .endTurn: return .endTurn
        }
    }
    public static func rankingEvent(hasEntries: Bool, wasCleared: Bool) -> SiegeVoiceEvent {
        hasEntries ? .rankingSaved : (wasCleared ? .rankingCleared : .rankingEmpty)
    }

    /// Only fictional/public reducer fields. No geometry, sensor values, user identity or hidden seed.
    public static func prompt(mission: SignalSiege, tone: SiegeHumor) -> String {
        """
        You are KIRA, a fictional salvage officer in Signal Siege. Reply in Russian in at most two short sentences.
        Tone: \(tone.instruction)
        Satirize the imaginary employer, absurd incentives and equipment. Do not insult the real player or target real social groups. No slurs, gore, real tragedies or advice to harm anyone.
        Public GAME facts: phase=\(mission.phase.rawValue); turn=\(mission.turn); health=\(mission.health); AP=\(mission.actions); relaySecured=\(mission.relaySecured).
        These are fictional game values, NOT physical measurements. Do not claim sensor access, alter scores or rules, invent observations, or issue executable commands. No preamble. No hidden reasoning.
        """
    }
}
