import type { Metadata,Viewport } from 'next';
import './globals.css';
import {sitePath} from '@/lib/site-path';
export const metadata:Metadata={title:'إدارة الأغنام',description:'أغنامك وحساباتك، في مكان واحد.',manifest:sitePath('/manifest.webmanifest'),appleWebApp:{capable:true,statusBarStyle:'default',title:'إدارة الأغنام'},icons:{icon:sitePath('/icon-192.png'),apple:sitePath('/apple-touch-icon.png')}};
export const viewport:Viewport={width:'device-width',initialScale:1,viewportFit:'cover',themeColor:'#195747'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="ar" dir="rtl"><body>{children}</body></html>;}
