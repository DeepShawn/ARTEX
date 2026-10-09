import packageJson from "../../package.json";

const currentYear = new Date().getFullYear();

export const APP_CONFIG = {
  name: "Autonomous Pentest Agent",
  version: packageJson.version,
  copyright: `© ${currentYear}, Autonomous Pentest Agent.`,
  meta: {
    title: "Autonomous Pentest Agent — 自主渗透测试控制台",
    description: "LLM 驱动的自主渗透测试系统控制台",
  },
};
