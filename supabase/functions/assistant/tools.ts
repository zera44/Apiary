// Опис інструментів для моделі. Виконує їх застосунок на телефоні (дані там),
// сервер лише передає опис моделі. Етап 3 додасть інструменти; порядок
// сталий - від нього залежить кеш.

export type ToolDef = {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
};

export const TOOLS: ToolDef[] = [];
