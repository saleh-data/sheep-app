export const basePath=process.env.NEXT_PUBLIC_BASE_PATH||'';
export const sitePath=(path:string)=>`${basePath}${path}`;
