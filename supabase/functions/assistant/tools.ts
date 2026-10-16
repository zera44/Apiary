// Опис інструментів для моделі. Виконує їх застосунок на телефоні (дані
// там): lib/assistant/assistant_tools.dart - назви й поля мають збігатися.
// Порядок і текст сталі - від них залежить кеш.
//
// Інструменти запису людина підтверджує карткою «Записати так?»; модель
// отримує {"status":"підтверджено", …} або {"status":"відхилено"}.

import { SCREENS } from './prompt.ts';

export type ToolDef = {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
};

const str = (description: string) => ({ type: 'string', description });
const obj = (properties: Record<string, unknown>, required: string[] = []) => ({
  type: 'object',
  properties,
  required,
  additionalProperties: false,
});

const HIVE_ID = str('id вулика з find_hives (e:… або g:…) або його назва, напр. «5»');

export const READ_TOOLS = ['open_screen', 'apiaries_list', 'find_hives', 'hive_history', 'stock_list', 'finance_summary'];
export const WRITE_TOOLS = ['record_inspection', 'stock_receive', 'stock_issue', 'add_finance_entry', 'create_reminder'];

export const TOOLS: ToolDef[] = [
  {
    name: 'open_screen',
    description:
      'Відкрити екран застосунку (опис екранів - у системному промпті). Для map - id або назва пасіки ' +
      '(можна без id, якщо пасіка одна), для hive - id вулика, для lesson - id уроку.',
    input_schema: obj({ screen: { type: 'string', enum: [...SCREENS] }, id: str('Необов\'язково: пасіка, вулик чи урок') }, ['screen']),
  },
  {
    name: 'apiaries_list',
    description: 'Список пасік: id, назва, кількість вуликів (група вуликів - один, як у find_hives).',
    input_schema: obj({}),
  },
  {
    name: 'find_hives',
    description:
      'Знайти вулики: за пасікою, назвою, терміном огляду (due: overdue - пора або прострочено, ' +
      'week - протягом 7 днів), останнім значенням параметра (parameter + value - «містить»), ' +
      'наявністю QR-коду (has_qr). Група вуликів (напр., лежак) - один вулик. ' +
      'Повертає короткий список: id, назва, пасіка, днів до огляду, останній огляд.',
    input_schema: obj({
      apiary: str('id або назва пасіки'),
      name: str('частина назви вулика'),
      due: { type: 'string', enum: ['overdue', 'week'] },
      parameter: str('назва параметра'),
      value: str('значення параметра (частина)'),
      has_qr: { type: 'boolean', description: 'true - лише з QR-кодом, false - лише без QR-коду' },
      limit: { type: 'integer', minimum: 1, maximum: 50 },
    }),
  },
  {
    name: 'hive_history',
    description: 'Історія вулика за останні days днів (типово 30): значення параметрів і нотатки.',
    input_schema: obj({ hive_id: HIVE_ID, days: { type: 'integer', minimum: 1, maximum: 365 } }, ['hive_id']),
  },
  {
    name: 'stock_list',
    description: 'Залишки на складі: назва, кількість, одиниця, low - якщо менше мінімуму.',
    input_schema: obj({ query: str('частина назви') }),
  },
  {
    name: 'finance_summary',
    description: 'Доходи, витрати й баланс за період (типово - з початку місяця), за категоріями.',
    input_schema: obj({ from: str('YYYY-MM-DD'), to: str('YYYY-MM-DD') }),
  },
  {
    name: 'record_inspection',
    description:
      'Записати огляд вулика: значення параметрів (назви - як у вулика), нотатку; дата обходу - ' +
      'сьогодні (mark_visited=false - не відмічати). Людина підтверджує карткою.',
    input_schema: obj(
      {
        hive_id: HIVE_ID,
        values: { type: 'object', description: '{назва параметра: значення}', additionalProperties: { type: 'string' } },
        note: str('нотатка огляду'),
        mark_visited: { type: 'boolean' },
      },
      ['hive_id'],
    ),
  },
  {
    name: 'stock_receive',
    description: 'Прихід на склад (купили, отримали). Людина підтверджує карткою.',
    input_schema: obj(
      { item: str('назва номенклатури'), amount: { type: 'number' }, total: { type: 'number', description: 'сума, грн' }, comment: str('коментар - лише якщо людина його сказала') },
      ['item', 'amount'],
    ),
  },
  {
    name: 'stock_issue',
    description: 'Списання зі складу (використали, віддали). Людина підтверджує карткою.',
    input_schema: obj({ item: str('назва номенклатури'), amount: { type: 'number' }, comment: str('коментар - лише якщо людина його сказала') }, ['item', 'amount']),
  },
  {
    name: 'add_finance_entry',
    description: 'Запис у фінанси: дохід чи витрата, сума, категорія (назва), дата. Людина підтверджує карткою.',
    input_schema: obj(
      {
        kind: { type: 'string', enum: ['income', 'expense'] },
        amount: { type: 'number' },
        category: str('назва категорії'),
        date: str('YYYY-MM-DD, типово сьогодні'),
        comment: str('коментар - лише якщо людина його сказала'),
      },
      ['kind', 'amount'],
    ),
  },
  {
    name: 'create_reminder',
    description: 'Разове нагадування сповіщенням на телефоні, за потреби - про вулик. Людина підтверджує карткою.',
    input_schema: obj(
      { text: str('що нагадати'), date: str('YYYY-MM-DD'), time: str('HH:MM, типово 09:00'), hive_id: HIVE_ID },
      ['text', 'date'],
    ),
  },
];
