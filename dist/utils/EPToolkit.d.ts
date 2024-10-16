/// <reference types="node" />
declare type IOptions = {
    beep: boolean;
    cut: boolean;
    tailingLine: boolean;
    encoding: string;
};
export declare function exchange_text(text: string, options: IOptions): Buffer;
export declare function exchange_text_ios(text: string, options: IOptions): string;
export {};
