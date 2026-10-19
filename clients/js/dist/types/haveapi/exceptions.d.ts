import { Client } from './client';
import type { Action } from './action';
export interface ProtocolError {
    name: string;
    message: string;
}
export interface UnresolvedArguments extends ProtocolError {
}
export interface UncancelableAction extends ProtocolError {
}
export interface Exceptions {
    ProtocolError: {
        new (msg: string): ProtocolError;
    };
    UnresolvedArguments: {
        new (action: Action): UnresolvedArguments;
    };
    UncancelableAction: {
        new (stateId: string | number, client: Client): UncancelableAction;
    };
}
