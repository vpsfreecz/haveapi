import type { ActionCall } from './action';
export interface ActionStateData {
    id: number;
    label?: string;
    finished?: boolean;
    status?: boolean;
    created_at?: string | null;
    updated_at?: string | null;
    can_cancel?: boolean;
    current?: number;
    total?: number;
    unit?: string;
}
export interface Progress {
    current: number | undefined;
    total: number | undefined;
    unit: string | undefined;
    toString(): string;
}
export interface ProgressConstructor {
    new (state: ActionStateData): Progress;
    prototype: Progress;
}
export interface ActionState {
    id: number;
    label: string | undefined;
    finished: boolean | undefined;
    status: boolean | undefined;
    createdAt: Date | string | null | undefined;
    updatedAt: Date | string | null | undefined;
    canCancel: boolean | undefined;
    progress: Progress;
    doStop?: boolean;
    doCancel?: boolean;
    cancelOpts?: ActionCall;
    stop(): void;
    shouldStop(): boolean;
    cancel(opts?: ActionCall): void;
    shouldCancel(): boolean;
}
export interface ActionStateConstructor {
    new (state: ActionStateData): ActionState;
    prototype: ActionState;
    Progress: ProgressConstructor;
}
/**
 * @class ActionState
 * @memberof HaveAPI.Client
 */
export declare const ActionState: ActionStateConstructor;
